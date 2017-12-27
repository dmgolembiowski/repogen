#!/bin/sh -x
checksum=`/bin/cat<<++|/bin/md5
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
++
`

# Usage:
# do.sh -	will mirror an OpenBSD CVS mirror
#		convert the cvs repo to bare git repos of src,xenocara,ports and www
#		create typical git repos of the bare git repos
#
#		when repeated, will update all of above with latest code 
#
#		user should aim it a particular openbsd rsync mirror 
#		and run it regularly to maintain updated git mirrors
#
# Steps:
# $ doas pkg_add git
# $ doas pkg_add cvs2gitdump
# $ doas pkg_add rsync
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
#
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

licenseok() {
	if [ $checksum != "32c66371f4be6ca567cd523f7f3c55a0" ]; then
		echo $0: license tampered, verify with https://cvsweb.openbsd.org/cgi-bin/cvsweb/src/share/misc/license.template?rev=HEAD  
		exit 1
	fi
}

licenseok

rsynchostpath=anoncvs.fr.openbsd.org/openbsd-cvs/

upsync=1 # rsync with upstream mirror 

# use a memory filesystem to host a copy of staging repo
# no speedup observed, we are cpubound with cvs2gitdump
memcache=1

# block device to mount mfs /m, typically your swap device
device=/dev/sd0b 

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

require() {
	binpath=/usr/local/bin/$binfile
	if [ ! -x $f ]; then
		echo "$0: error cannot run $binpath"
		exit 1
	fi
	if [ ! -f $binpath ]; then
		echo "$0: error cannot without $binpath, install it"
		exit 1
	fi
}

for binfile in rsync git cvs2gitdump
do
	require $binfile
done
cvs2gitdump=/usr/local/bin/cvs2gitdump

# memcache needs doas, if unable to run command as root, then no memcache
if [ $memcache -eq 1 ]; then
	/usr/bin/doas -n /usr/bin/id
	if [ $? -ne 0 ]; then
		memcache=0
		echo MARK unset memcache as unable to do passwordless doas
	fi
fi

mark() {
	echo -n "MARK "
	date
}

mark

physmem=`sysctl -n hw.physmem`
memlim=10737418240 # 10GB
# use memory files if we have more than 10GB RAM because cvsrepo0 is about 6.3GB
if [ $physmem -lt $memlim ]; then
	memcache=0
fi

# incoming cvs repository - cvsrepo0
cvsrepo=`pwd`/cvsrepo0
if [ $upsync -eq 1 ]; then
	mark
	/usr/local/bin/rsync -az --delete rsync://$rsynchostpath cvsrepo0
	mark
fi

# sync incoming with staging on disk
stagesync=1	# do not change
if [ $stagesync -eq 1 ]; then
	mark
	/usr/local/bin/rsync -a --delete cvsrepo0/ cvsrepo1
	mark
	cvsrepo=`pwd`/cvsrepo1
fi

# sync staging on disk with staging in memory
reuse=1 # reuse memcache across runs
if [ $memcache -eq 1 ]; then
	mark
	if [ -d /m ]; then
		if [ $reuse -eq 0 ]; then
			/usr/bin/doas /sbin/umount -f /m
			/bin/sleep 10
			/usr/bin/doas /bin/rmdir /m
		fi
	fi
	if [ ! -d /m/cvsrepo1 ]; then
		/usr/bin/doas /bin/mkdir /m
		/usr/bin/doas /sbin/mount -t mfs -o rw,noatime,noexec,nodev,nosuid,-s=9g $device /m
		/usr/bin/doas /sbin/chown $USER /m
		/sbin/mount
		/bin/ls -ld /m
		/bin/df -h
		/bin/sleep 10
	fi

	mark
	/usr/local/bin/rsync -a --delete cvsrepo1/ /m/cvsrepo1
	mark

	cvsrepo=/m/cvsrepo1
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
		/usr/local/bin/git init --bare $gitrepo
		mark
		if [ $pipeonly -eq 1 ]; then
			$cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo | \
					/usr/local/bin/git --git-dir $gitrepo fast-import
		else
			ts=`date +%Y%m%d:%H%M%S%z` 
			dumpfile="dump0.${module}-${ts}" 
			$cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo | \
					/usr/bin/tee $dumpfile | \
					/usr/local/bin/git --git-dir $gitrepo fast-import
		fi
		mark
		# create non bare git (typical) git repo from bare repo
		/bin/rm -f ${module}0
		/usr/local/bin/git clone $gitrepo ${module}0
	else
		mark
		if [ $pipeonly -eq 1 ]; then
			if [ $memcache -eq 1 ]; then
				# load gitrepo into cache
				diskgitrepo=$gitrepo
				memgitrepo=/m/$repodir
				if [ ! -d $memgitrepo ]; then
					/usr/bin/doas /sbin/chown $USER /m
					/bin/cp -r ${diskgitrepo}/ /m
					mark
				fi
				# verify that copy with an sync
				/usr/local/bin/rsync -a --delete ${diskgitrepo}/ $memgitrepo
				mark

				# compare in memory cvs and git repo but write to disk git repo
				$cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo $memgitrepo | \
						/usr/local/bin/git --git-dir $diskgitrepo fast-import

				mark

				# remove in memory git repo
				/bin/rm -fr $memgitrepo
				unset diskgitrepo memgitrepo

			else
				$cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo $gitrepo | \
						/usr/local/bin/git --git-dir $gitrepo fast-import
			fi
		else
			ts=`date +%Y%m%d:%H%M%S%z`
			dumpfile="dump1.${module}-${ts}"
			$cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo $gitrepo | \
					/usr/bin/tee $dumpfile | \
					/usr/local/bin/git --git-dir $gitrepo fast-import
		fi
		mark
		# update non bare git repo (typical) from bare repo
		if [ ! -d ${module}0 ]; then
			/usr/local/bin/git clone $gitrepo ${module}0
		fi
		cd ${module}0 && /usr/local/bin/git pull && cd ..
	fi

done

# remove memcache
if [ $memcache -eq 1 ]; then
	if [ $reuse -eq 0 ]; then
		if [ -d /m ]; then
			/usr/bin/doas /sbin/umount -f /m
			/bin/sleep 10
			/usr/bin/doas /bin/rmdir /m
		fi
	fi
fi

mark
exit 0
