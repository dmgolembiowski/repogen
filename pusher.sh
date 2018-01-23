#!/bin/sh

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

set -x

markid() {
	date; echo $id
}

if [ -f STARTED ]; then
	firstpush=0
else
	firstpush=1
fi

present=`git remote -v | awk '{ if ($1 == "github") print $0; }' | wc -l`
if [ $present -eq 0 ]; then
	echo "$0: error no remote called github present, kindly create it."
	git remote -v
	exit 1
fi

run="echo"
run=""
git log --reverse | grep ^commit | cat -n | awk '{ if ($1 % 1000 == 1) print $0; }' | awk '{ print $3; }' |  tee COMMITS 
for id in `cat COMMITS`
do
	if [ $firstpush -eq 1 ]; then
		$run git push github ${id}:refs/heads/master
		firstpush=0
		$run markid | $run tee STARTED
		$run markid | $run tee DONE
	else
		$run git push github $id:master
		$run markid | $run tee -a DONE
	fi
done
git push --mirror github master

exit 0
