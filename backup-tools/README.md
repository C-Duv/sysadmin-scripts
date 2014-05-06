Backup tools
============

Collection of scripts used to perform backups.

* `lftp/lftpBackup`: Quite old Perl script that compress and backup files, MySQL databases and LDAP tree to a FTP server (via [LFTP](http://lftp.yar.ru)).
* `duplicity/duplicityBackup`: Newer Perl script that does the same job as above but uses [duplicity](http://duplicity.nongnu.org) as a backend to handle incremental/full backup, encryption and retention rules. Can transfer to FS, FTP and SSH/SFTP locations.