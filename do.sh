#!/bin/sh -xvf

#------------------------------------------------------------------------------
#
# Copyright (c) 2017 Dinesh Thirumurthy <dinesh.thirumurthy@gmail.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
#------------------------------------------------------------------------------

# Usage:
# do.sh -	will mirror an OpenBSD CVS mirror, make a copy of that mirror, 
#		and convert the copy to bare git mirrors and make clones of those
#		and when called will do the same and update relevant git mirrors
#		user should aim it a particular openbsd rsync mirror 
#		and run it regularly to maintain updated git mirrors
#
# $ doas pkg_add cvs2gitdump
# $ mkdir repo
# $ cd repo
# $ git clone https://github.com/hakrtech/repogen.git
# $ chmod +x repogen/do.sh 
# $ ./repogen/do.sh
# will generate 
# 1.	cvsrepo0/	- cvs repository mirrored from france
# 2.	cvsrepo1/	- staging version of above repository
# 3.	bare.src.git/	- bare git repository of src module of cvs repo
# 4.	bare.xenocara.git/	- same for xenocara
# 5.	bare.ports.git/	- same for ports
# 6.	bare.www.git/	- same for www
# 7.	src0/		- checkout of master from bare repository for src
# 8.	xenocara0/	- same for xenocara
# 9.	ports0/		- same for ports
# 10.	www0/		- same for www
# and you run it again to update the same
# $ ./repogen/do.sh
# will update
# 1.	cvsrepo0/	- update cvs repository mirrored from france
# 2.	cvsrepo1/	- update staging version of above repository
# 3.	bare.src.git/	- update bare git repository of src module of cvs repo
# 4.	bare.xenocara.git/	- update same for xenocara
# 5.	bare.ports.git/	- update same for ports
# 6.	bare.www.git/	- update same for www
# 7.	src0/		- update checkout of master from bare repository for src
# 8.	xenocara0/	- update same for xenocara
# 9.	ports0/		- update same for ports
# 10.	www0/		- update same for www

rsynchostpath=anoncvs.fr.openbsd.org/openbsd-cvs/

upsync=1		 $ rsync with upstream mirror 
memcache=1	 # use a memory filesystem to host a copy of staging repo
						 # no speedup observed, we are cpubound with cvs2gitdump
device=/dev/sd0b # block device to mount mfs /m, typically your swap device

# unset memcache if !openbsd
os=`uname -s`
if [ $os != "OpenBSD" ]; then
	# :-( no openbsd mfs, so no memcache
	memcache=0
	echo MARK unset memcache as $os is not OpenBSD
fi

# need blk device for memcache (mfs)
if [ $memcache -eq 1 ]; then
	if [ ! -b $device ]; then
		echo "$0: error no such block device $device"
		exit 1
	fi
fi

# incoming cvs repository - cvsrepo0
cvsrepo=`pwd`/cvsrepo0
if [ $upsync -eq 1 ]; then
	echo MARK
	date
	rsync -avz --delete rsync://$rsynchostpath cvsrepo0
	date
fi

# sync incoming with staging on disk
stagesync=1	# do not change
if [ $stagesync -eq 1 ]; then
	echo MARK
	rsync -a --delete cvsrepo0/ cvsrepo1
	date
	echo MARK
	cvsrepo=`pwd`/cvsrepo1
fi

# sync staging on disk with staging in memory
if [ $memcache -eq 1 ]; then
	echo MARK
	date
	physmem=`sysctl -n hw.physmem`
	memlim=10737418240 # 10GB
	# use memory files if we have more than 10GB RAM because cvsrepo0 is about 6.3GB
	if [ $physmem -gt $memlim ]; then
		if [ -d /m ]; then
			doas umount /m; sleep 1
			doas rmdir /m
		fi
		doas mkdir -p /m
		doas mount -t mfs -o rw,nodev,nosuid,-s=9g $device /m
		doas chown $USER /m
		mount
		ls -ld /m
		df -h
		sleep 5

		if [ ! -d /m/cvsrepo1 ]; then
			doas chown -R $USER /m
			mkdir -p /m/cvsrepo1
			cp -r cvsrepo1/ /m
			date
			echo MARK
		fi

		rsync -a --delete cvsrepo1/ /m/cvsrepo1
		date
		echo MARK

		cvsrepo=/m/cvsrepo1
	fi
fi
echo MARK cvsrepo is $cvsrepo

pipeonly=1
savedir=`pwd`
for module in src xenocara ports www
do
	cd $savedir
	repodir=bare.${module}.git
	gitrepo=`pwd`/bare.${module}.git
	if [ ! -d $gitrepo ]; then
		git init --bare $gitrepo
		echo MARK
		date
		if [ $pipeonly -eq 1 ]; then
			cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo | \
					git --git-dir $gitrepo fast-import
		else
			ts=`date +%Y%m%d:%H%M%S%z` 
			dumpfile="dump0.${module}-${ts}" 
			cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo | \
					tee $dumpfile | \
					git --git-dir $gitrepo fast-import
		fi
		date
		echo MARK
		# create non bare git (typical) git repo from bare repo
		/bin/rm -f ${module}0
		git clone $gitrepo ${module}0
	else
		echo MARK
		date
		if [ $pipeonly -eq 1 ]; then
			if [ $memcache -eq 1 ]; then
				# load gitrepo into cache
				diskgitrepo=$gitrepo
				memgitrepo=/m/$repodir
				if [ ! -d $memgitrepo ]; then
					doas chown $USER /m
					cp -r ${diskgitrepo}/ /m
					date
					echo MARK
				fi
				# verify that copy with an sync
				rsync -a --delete ${diskgitrepo}/ $memgitrepo
				date
				echo MARK

				# compare in memory cvs and git repo but write to disk git repo
				cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo $memgitrepo | \
						git --git-dir $diskgitrepo fast-import

				date
				echo MARK

				# remove in memory git repo
				rm -fr $memgitrepo
				unset diskgitrepo memgitrepo

			else
				cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo $gitrepo | \
						git --git-dir $gitrepo fast-import
			fi
		else
			ts=`date +%Y%m%d:%H%M%S%z`
			dumpfile="dump1.${module}-${ts}"
			cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo $gitrepo | \
					tee $dumpfile | \
					git --git-dir $gitrepo fast-import
		fi
		date
		echo MARK
		# update non bare git repo (typical) from bare repo
		if [ ! -d ${module}0 ]; then
			git clone $gitrepo ${module}0
		fi
		cd ${module}0 && git pull && cd ..
	fi

done
# remove memcache
if [ $memcache -eq 1 ]; then
	if [ -d /m ]; then
		doas umount /m
		doas rmdir /m
	fi
fi
exit 0
