#!/bin/sh -xv

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
#
# $ mkdir repo
# $ cd repo
# $ git clone https://github.com/hakrtech/repogen.git
# chmod +x repogen/do.sh 
# ./repogen/do.sh
# will generate 
# 1.  cvsrepo0/		- cvs repository mirrored from france
# 2.  cvsrepo1/		- staging version of above repository
# 3.  bare.src.git/	- bare git repository of src module of cvs repo
# 4.  bare.xenocara.git/- same for xenocara
# 5.  bare.ports.git/ 	- same for ports
# 6.  bare.www.git/	- same for www
# 7.  src0/		- checkout of master from bare repository for src
# 8.  xenocara0/	- same for xenocara
# 9.  ports0/		- same for ports
# 10. www0/		- same for www

rsynchostpath=anoncvs.fr.openbsd.org/openbsd-cvs/

upsync=1
stagesync=1
# incoming cvs repository - cvsrepo0
if [ $upsync -eq 1 ]; then
  echo MARK
  date
  rsync -avz rsync://$rsynchostpath cvsrepo0
  date
fi

# sync incoming with staging on disk
if [ $stagesync -eq 1 ]; then
  echo MARK
  rsync -a cvsrepo0/ cvsrepo1
  date
  echo MARK
fi

# sync staging on disk with staging in memory
cvsrepo=`pwd`/cvsrepo1
memsync=0 # use a memory filesystem to host a copy of staging repo
          # no speedup observed, we are cpubound with cvs2gitdump
device=/dev/sd0b
if [ $memsync -eq 1 ]; then
  echo MARK
  date
  physmem=`sysctl -n hw.physmem`
  memlim=10737418240 # 10GB
  # use memory files if we have more than 10GB RAM because cvsrepo0 is about 6.3GB
  if [ $physmem -gt $memlim ]; then
    if [ ! -d /m ]; then
      if [ ! -b $device ]; then
        echo "$0: error no such block device $device"
        exit 1
      fi
      doas mount -t mfs -o rw,nodev,nosuid,-s=8g $device /m
      doas chown $USER /m
    fi
    if [ ! -d /m/cvsrepo1 ]; then
      doas chown -R $USER /m
      mkdir -p /m/cvsrepo1
      cp -r cvsrepo1/ /m
      date
      echo MARK
    fi
    rsync -a cvsrepo1/ /m/cvsrepo1
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
      cvs2gitdump -k OpenBSD -e openbsd.org -m $module $cvsrepo | \
          git --git-dir $gitrepo fast-import
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
exit 0
