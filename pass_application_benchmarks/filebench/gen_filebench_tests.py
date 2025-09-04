# Base template content
varmail_template_content = """
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
#
# Copyright 2007 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#

enable lathist

set $dir=/tmp
set $nfiles=200000
set $meandirwidth=1000000
set $filesize=cvar(type=cvar-gamma,parameters=mean:163840;gamma:1.5)
set $nthreads=16
set $iosize=1m
set $meanappendsize=16k

define fileset name=bigfileset,path=$dir,size=$filesize,entries=$nfiles,dirwidth=$meandirwidth,prealloc=80

define process name=filereader,instances=4
{
  thread name=filereaderthread,memsize=10m,instances=$nthreads
  {
    flowop deletefile name=deletefile1,filesetname=bigfileset
    flowop createfile name=createfile2,filesetname=bigfileset,fd=1
    flowop appendfilerand name=appendfilerand2,iosize=$meanappendsize,fd=1
    flowop fsync name=fsyncfile2,fd=1
    flowop closefile name=closefile2,fd=1
    flowop openfile name=openfile3,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile3,fd=1,iosize=$iosize
    flowop appendfilerand name=appendfilerand3,iosize=$meanappendsize,fd=1
    flowop fsync name=fsyncfile3,fd=1
    flowop closefile name=closefile3,fd=1
    flowop openfile name=openfile4,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile4,fd=1,iosize=$iosize
    flowop closefile name=closefile4,fd=1
  }
}

echo  "Varmail Version 3.0 personality successfully loaded"

run 180

"""

# Python script to generate files
for i in range(1, 11):
    file_content = varmail_template_content.replace("set $dir=/tmp", f"set $dir=/mnt/test_disk_{i}")
    file_name = f"varmail_{i}.f"
    with open(file_name, "w") as file:
        file.write(file_content)

print("Files varmail_1.f to varmail_10.f have been created.")

# Base template content
networkfs_template_content = """
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
# Copyright 2009 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#
# $dir - directory for datafiles
# $eventrate - event generator rate (0 == free run)
# $nfiles - number of data files
# $nthreads - number of worker threads

enable lathist

set $dir=/tmp
set $cached=false
set $eventrate=10
set $meandirwidth=20
set $nthreads=16
set $nfiles=200000
set $sync=false
set $totalfiles=$nfiles * $eventrate

eventgen rate=$eventrate

define randvar name=$wrtiosize, type=tabular, min=1k, round=1k, randtable =
{{ 0,   1k,    7k},
 {50,   9k,   15k},
 {14,  17k,   23k},
 {14,  33k,   39k},
 {12,  65k,   71k},
 {10, 129k,  135k}
}

define randvar name=$rdiosize, type=tabular, min=8k, round=1k, randtable =
{{85,   8k,   8k},
 { 8,  17k,  23k},
 { 4,  33k,  39k},
 { 2,  65k,  71k},
 { 1, 129k, 135k}
}

define randvar name=$filesize, type=tabular, min=1k, round=1k, randtable =
{{33,   1k,    1k},
 {21,   1k,    3k},
 {13,   3k,    5k},
 {10,   5k,   11k},
 {08,  11k,   21k},
 {05,  21k,   43k},
 {04,  43k,   85k},
 {03,  85k,  171k},
 {02, 171k,  341k},
 {01, 341k, 1707k}
}

define randvar name=$fileidx, type=gamma, min=0, gamma=100

define fileset name=bigfileset,path=$dir,size=$filesize,entries=$totalfiles,dirwidth=$meandirwidth,prealloc=60,cached=$cached

define flowop name=rmw, $filesetrmw
{
  flowop openfile name=openfile1,filesetname=$filesetrmw,indexed=$fileidx,fd=1
  flowop readwholefile name=readfile1,iosize=$rdiosize,fd=1
  flowop createfile name=newfile2,filesetname=$filesetrmw,indexed=$fileidx,fd=2
  flowop writewholefile name=writefile2,fd=2,iosize=$wrtiosize,srcfd=1
  flowop closefile name=closefile1,fd=1
  flowop closefile name=closefile2,fd=2
  flowop deletefile name=deletefile1,fd=1
}

define flowop name=launch, $filesetlch
{
  flowop openfile name=openfile3,filesetname=$filesetlch,indexed=$fileidx,fd=3
  flowop readwholefile name=readfile3,iosize=$rdiosize,fd=3
  flowop openfile name=openfile4,filesetname=$filesetlch,indexed=$fileidx,fd=4
  flowop readwholefile name=readfile4,iosize=$rdiosize,fd=4
  flowop closefile name=closefile3,fd=3
  flowop openfile name=openfile5,filesetname=$filesetlch,indexed=$fileidx,fd=5
  flowop readwholefile name=readfile5,iosize=$rdiosize,fd=5
  flowop closefile name=closefile4,fd=4
  flowop closefile name=closefile5,fd=5
}

define flowop name=appnd, $filesetapd
{
  flowop openfile name=openfile6,filesetname=$filesetapd,indexed=$fileidx,fd=6
  flowop appendfilerand name=appendfilerand6,iosize=$wrtiosize,fd=6
  flowop closefile name=closefile6,fd=6
}

define process name=netclient,instances=1
{
  thread name=fileuser,memsize=10m,instances=$nthreads
  {
    flowop launch name=launch1, iters=1, $filesetlch=bigfileset
    flowop rmw name=rmw1, iters=6, $filesetrmw=bigfileset
    flowop appnd name=appnd1, iters=3, $filesetapd=bigfileset
    flowop statfile name=statfile1,filesetname=bigfileset,indexed=$fileidx
    flowop eventlimit name=ratecontrol
  }
}

echo  "NetworkFileServer Version 1.0 personality successfully loaded"

run 180

"""

# Python script to generate files
for i in range(1, 11):
    file_content = networkfs_template_content.replace("set $dir=/tmp", f"set $dir=/mnt/test_disk_{i}")
    file_name = f"networkfs_{i}.f"
    with open(file_name, "w") as file:
        file.write(file_content)

print("Files networkfs_1.f to networkfs_10.f have been created.")

# Base template content
webserver_template_content = """
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
#
# Copyright 2007 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#

enable lathist

set $dir=/tmp
set $nfiles=200000
set $meandirwidth=20
set $filesize=cvar(type=cvar-gamma,parameters=mean:163840;gamma:1.5)
set $nthreads=100
set $iosize=1m
set $meanappendsize=16k

define fileset name=bigfileset,path=$dir,size=$filesize,entries=$nfiles,dirwidth=$meandirwidth,prealloc=100,readonly
define fileset name=logfiles,path=$dir,size=$filesize,entries=1,dirwidth=$meandirwidth,prealloc

define process name=filereader,instances=1
{
  thread name=filereaderthread,memsize=10m,instances=$nthreads
  {
    flowop openfile name=openfile1,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile1,fd=1,iosize=$iosize
    flowop closefile name=closefile1,fd=1
    flowop openfile name=openfile2,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile2,fd=1,iosize=$iosize
    flowop closefile name=closefile2,fd=1
    flowop openfile name=openfile3,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile3,fd=1,iosize=$iosize
    flowop closefile name=closefile3,fd=1
    flowop openfile name=openfile4,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile4,fd=1,iosize=$iosize
    flowop closefile name=closefile4,fd=1
    flowop openfile name=openfile5,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile5,fd=1,iosize=$iosize
    flowop closefile name=closefile5,fd=1
    flowop openfile name=openfile6,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile6,fd=1,iosize=$iosize
    flowop closefile name=closefile6,fd=1
    flowop openfile name=openfile7,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile7,fd=1,iosize=$iosize
    flowop closefile name=closefile7,fd=1
    flowop openfile name=openfile8,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile8,fd=1,iosize=$iosize
    flowop closefile name=closefile8,fd=1
    flowop openfile name=openfile9,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile9,fd=1,iosize=$iosize
    flowop closefile name=closefile9,fd=1
    flowop openfile name=openfile10,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile10,fd=1,iosize=$iosize
    flowop closefile name=closefile10,fd=1
    flowop appendfilerand name=appendlog,filesetname=logfiles,iosize=$meanappendsize,fd=2
  }
}

echo  "Web-server Version 3.1 personality successfully loaded"

run 180

"""

# Python script to generate files
for i in range(1, 11):
    file_content = webserver_template_content.replace("set $dir=/tmp", f"set $dir=/mnt/test_disk_{i}")
    file_name = f"webserver_{i}.f"
    with open(file_name, "w") as file:
        file.write(file_content)

print("Files webserver_1.f to wenserver_10.f have been created.")

fileserver_template_content = """
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
#
# Copyright 2008 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
#

enable lathist

set $dir=/tmp
set $nfiles=10000
set $meandirwidth=20
# set $filesize=cvar(type=cvar-gamma,parameters=mean:131072;gamma:1.5)
set $filesize=cvar(type=cvar-gamma,parameters=mean:1310720;gamma:1.5)
set $nthreads=50
set $iosize=1m
set $meanappendsize=16k

define fileset name=bigfileset,path=$dir,size=$filesize,entries=$nfiles,dirwidth=$meandirwidth,prealloc=80

define process name=filereader,instances=1
{
  thread name=filereaderthread,memsize=10m,instances=$nthreads
  {
    flowop createfile name=createfile1,filesetname=bigfileset,fd=1
    flowop writewholefile name=wrtfile1,srcfd=1,fd=1,iosize=$iosize
    flowop closefile name=closefile1,fd=1
    flowop openfile name=openfile1,filesetname=bigfileset,fd=1
    flowop appendfilerand name=appendfilerand1,iosize=$meanappendsize,fd=1
    flowop closefile name=closefile2,fd=1
    flowop openfile name=openfile2,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile1,fd=1,iosize=$iosize
    flowop closefile name=closefile3,fd=1
    flowop deletefile name=deletefile1,filesetname=bigfileset
    flowop statfile name=statfile1,filesetname=bigfileset
  }
}

echo  "File-server Version 3.0 personality successfully loaded"

run 180
"""
# Python script to generate files
for i in range(1, 11):
    file_content = fileserver_template_content.replace("set $dir=/tmp", f"set $dir=/mnt/test_disk_{i}")
    file_name = f"fileserver_{i}.f"
    with open(file_name, "w") as file:
        file.write(file_content)

print("Files fileserver_1.f to fileserver_10.f have been created.")

fileburst_template_content = """
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
#
# Copyright 2008 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
# Copyright 2025 Dedong Xie. All rights reserved.
# Use is subject to license terms.
#

enable lathist

set $dir=/tmp
set $nfiles=10000
set $meandirwidth=20
# set $filesize=cvar(type=cvar-gamma,parameters=mean:131072;gamma:1.5)
set $filesize=cvar(type=cvar-gamma,parameters=mean:1310720;gamma:1.5)
set $nthreads=128
set $iosize=32k
set $meanappendsize=4k
set $burst_interval=10

define fileset name=bigfileset,path=$dir,size=$filesize,entries=$nfiles,dirwidth=$meandirwidth,prealloc=80

define process name=filewriterforeground,instances=1
{
  thread name=filewriterthread, memsize=10m,instances=$nthreads
  {
    flowop delay name=sleep_foreground,value=$burst_interval
    flowop openfile name=openfile1,filesetname=bigfileset,fd=1
    flowop appendfile name=burstwrite1,filesetname=bigfileset,fd=1,iosize=$meanappendsize,iters=10,directio,dsync
    flowop closefile name=closefile2,fd=1
  }
}

define process name=filereaderbackground,instances=1
{
  thread name=filereaderthread,memsize=10m,instances=1
  {
    flowop createfile name=createfile1,filesetname=bigfileset,fd=1
    flowop writewholefile name=wrtfile1,srcfd=1,fd=1,iosize=$iosize
    flowop closefile name=closefile1,fd=1
    flowop openfile name=openfile2,filesetname=bigfileset,fd=1
    flowop readwholefile name=readfile1,fd=1,iosize=$iosize
    flowop closefile name=closefile3,fd=1
    flowop deletefile name=deletefile1,filesetname=bigfileset
    flowop statfile name=statfile1,filesetname=bigfileset
  }
}

echo  "File-burst Version 0.1 personality successfully loaded"

run 180
"""
# Python script to generate files
for i in range(1, 11):
    file_content = fileburst_template_content.replace("set $dir=/tmp", f"set $dir=/mnt/test_disk_{i}")
    file_name = f"fileburst_{i}.f"
    with open(file_name, "w") as file:
        file.write(file_content)

print("Files fileburst_1.f to fileburst_10.f have been created.")

filetest_template_content = """
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
#
# Copyright 2008 Sun Microsystems, Inc.  All rights reserved.
# Use is subject to license terms.
# Copyright 2025 Dedong Xie. All rights reserved.
# Use is subject to license terms.
#

enable lathist

set $dir=/tmp
set $nfiles=10000
set $meandirwidth=20
# set $filesize=cvar(type=cvar-gamma,parameters=mean:131072;gamma:1.5)
# set $filesize=cvar(type=cvar-gamma,parameters=mean:1310720;gamma:1.5)
set $filesize=128k
set $nprocs=6
set $nthreads=24
set $iosize=32k
set $meanappendsize=4k
set $burst_interval=10
set $directio=1

define fileset name=bigfileset,path=$dir,size=$filesize,entries=$nfiles,dirwidth=$meandirwidth,prealloc

define process name=timer,instances=1
{
  thread name=timerthread, memsize=10m,instances=1
  {
    flowop delay name=sleep_foreground,value=$burst_interval
    # flowop hog name=myhog,value=5000
    flowop wakeup name=wakeupbursts, target=my_block
  }
}

define process name=filewriterforeground,instances=$nprocs
{
  thread name=filewriterthread, memsize=10m,instances=$nthreads
  {
    flowop block name=my_block
    # flowop openfile name=openfile1,filesetname=bigfileset,fd=1
    # flowop appendfile name=burstwrite1,filesetname=bigfileset,fd=1,iters=10000,iosize=$meanappendsize,directio=1,dsync
    flowop write name=testwrite1,filesetname=bigfileset,iosize=$meanappendsize,random,directio,dsync,iters=3000
    # flowop closefile name=closefile2,fd=1
  }
}

# define process name=filewriterbackground,instances=1
# {
#   thread name=filewriterthread, memsize=10m,instances=4
#   {
#     flowop write name=testwrite1,filesetname=bigfileset,iosize=$meanappendsize,random,directio,dsync
#   }
# }

echo  "File-burst Version 0.1 personality successfully loaded"

run 60
"""
# Python script to generate files
for i in range(1, 11):
    file_content = filetest_template_content.replace("set $dir=/tmp", f"set $dir=/mnt/test_disk_{i}")
    file_name = f"filetest_{i}.f"
    with open(file_name, "w") as file:
        file.write(file_content)

print("Files filetest_1.f to filetest_10.f have been created.")