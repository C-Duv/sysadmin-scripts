Duplicity Backup tool
=====================

This is a Perl script to perform backups via [duplicity](http://duplicity.nongnu.org).

TL;DR: Reads a YAML configuration file describing what folder/database/LDAP tree to backup and where to store theses backups, then run duplicity with accordingly.

Usage
-----

See `duplicityBackup --help` for command usage, `duplicityBackup --man` for more details.

Quick start
-----------

1. Install pre-requisites:
   * [duplicity](http://duplicity.nongnu.org) (it's in python BTW), which may require some other libs depending on where to backup
   * Perl modules:
     * Switch
     * List::Util
     * Hash::Merge::Simple
     * Getopt::Long
     * Pod::Usage
     * Log::Message::Simple
     * DateTime
     * Date::Parse
     * File::Basename
     * File::chmod
     * File::Path
     * File::Spec
     * URI
     * Capture::Tiny
     * YAML::XS
2. Create a blank configuration file `MyConfig.yml`:
    
    ```sh
    duplicityBackup create-config MyConfig.yml
    ```
3. Adapt obtained configuration file:
    
    Set server name, passwords, locations of file to backup and databases to dump, hostname/ip and SSH credentials of a server where to backup to.
    ```yaml
    # 
    # Backup configuration
    # 
    
    ---
    backupedServerName: MyHomeServer           # Friendly name of the server
    workingBasePath:    /tmp/backup/workingdir # Temporary local storage base path (used when dumping data)
    
    Duplicity:
      binPath: /usr/bin/duplicity          # Provide Duplicity program filepath
      archiveDir: /datas/backup/archiveDir # Provide a directory to use as duplicity's archive directory
      gpgPassphrase: 1Secret!              # Passphrase to use for encryption
    Services:
      FileSystem:
        localDisk: # Some friendly-name here
          enabled: 1                        # Enable backup of FS content
          type:    FileSystem
          subdir:  theLocalDisk/            # Store under this subdirectory
          options:
            pathsToBackup:                  # Want to backup theses folders
            - /etc
            - /root/
            - /home/user/some secret stuff
          duplicityOptions:
          - --exclude **/root/.secret       # Exclude this very secret stuff from backup
      
      Mysql: # MySQL Services
        mysql: # Again, some friendly-name
          enabled: 1                        # Enable backup of MySQL server
          type:    Mysql
          subdir:  mysqlServer/             # Store under this subdirectory
          options:
            host:                  localhost
            port:                  3306
            user:                  backup
            password:              some-secure-password
            mysqlclientfilepath:   /usr/bin/mysql        # Provide mysql and
            mysqldumpfilepath:     /usr/bin/mysqldump    # mysqldump program filepaths
            databasesToBackup: # Backup following databases:
              wordpress:
              webapp:
              - --single-transaction --quick
    
    Storages:
      Ssh:
        secureArchiveNas: # Got a NAS to store my stuff
          enabled: 1 # Enable backup here
          type:    Ssh
          options:
            host:     archive.example.com
            port:     4242
            user:     backup-storer
            password: some-secure-password
            path:     //data/bckups/%=backupedServerName%/ # Absolute path on NAS
          duplicity:
            fullIfOlder:              14D # Full every 14 days
            numberOfFullBackupToKeep: 5   # Cleaning is done when I have 10 full backups
    ```
4. Run backup:
    
    ```sh
    duplicityBackup --config MyConfig.yml
    ```

To-do list
----------

* Perform a check of the just-finished backup.
* Use specific duplicity options for a given file system path.
* Implement hooks system so that one can run commands before/after and/or on success/fail of any service (eg. perform a MySQL server flush or shutdown).
* Implement "list-storages-locations" action that gives nice ready-to-use duplicity URLs of every configured storage.
* Implement "list-files <some_location>" action that maps to `duplicity list-current-files <location_target_url>` (conveniently configured with passphrase and other stuff).
* Implement "verbose" flag.
* Better verification of temporary working directory content on backup end.
* Write log file on error.