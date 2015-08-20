# Udacity - Full Stack Nanodegree (FSND) Project 2 - Tournament

this code has been downloaded from https://github.com/wstoettinger/Udacity-FSND-P2-vm

(c) 2015 Wolfgang Stöttinger

## Instructions

### instralling vagrant and virtual box
- download and install vagrant and virtual box
- make sure virtual box is properly configured and virtualizing is activated in your computers BIOS settings (@UDACITY: you could add this to your instructions)
- open your console in the `vagrant` folder and type `vagrant up` ... the virtual machine is being initialized for the first time
- type `vagrant ssh` for a secure terminal connection to the virtual machine

### creating the database
- `cd` into the `torunament` subfolder
- run the `psql` command
- type `\i tournament.sql` to run the database script
- exit psql by typing `\q`

### running the py test script
- type `python tournament_test.py` to execute the test script
- tada! all 9 (including 1 udacious extra test) tests should work :)
