#!/usr/bin/perl

# 
# Backup script
# 
# Backups data of file system and various services to a FTP server.
# 
# @version 0.1
# 
# @requires lftp (Sophisticated file transfer program)
# @requires Perl "Date::Format"
# @requires Perl "Date::Parse"
# @requires Perl "Time::Piece"
# @requires Perl "File::Basename"
# @requires Perl "Log::Message::Simple"
# @requires Perl "YAML::XS"


##### Modules #####
use Date::Format; # Debian package "libtimedate-perl"
use Date::Parse; # Debian package "libtimedate-perl"

use Time::Piece;

use File::Basename;
use File::Spec;

use Log::Message::Simple qw[:STD :CARP];

use YAML::XS; # Debian package "libyaml-libyaml-perl"
##### /Modules #####



##### Constants #####
use constant {
	SERVICE_TYPE_FILESYSTEM => 'FileSystem',
	SERVICE_TYPE_LDAP       => 'Ldap',
	SERVICE_TYPE_MYSQL      => 'Mysql',
};
##### /Constants #####



##### Configuration #####
my $configFilepath = File::Spec->catdir(File::Basename::dirname($0), 'config.yml'); #TODO: Allow program option/parameter to override
my $config = YAML::XS::LoadFile($configFilepath);

$backupedServerName = $config->{'backupedServerName'};

$workingBasePath = $config->{'workingBasePath'};

my $services = $config->{'Services'};

my $externalStorage = $config->{'ExternalStorage'};

# Logger:
local $Log::Message::Simple::MSG_FH = \*STDOUT;
local $Log::Message::Simple::ERROR_FH = \*STDOUT;
local $Log::Message::Simple::DEBUG_FH = \*STDOUT;
$Log::Message::Simple::log_debug = $config->{'log_debug'};
##### /Configuration #####



##### Functions #####

## Logger ##

sub loggedMsg {
	Log::Message::Simple::msg('' . (substr `date -u +'%F %H:%M:%S %Z'`, 0, -1) . ' - ' . $_[0], 1);
}

sub loggedError {
	Log::Message::Simple::error('' . (substr `date -u +'%F %H:%M:%S %Z'`, 0, -1) . ' - ' . $_[0], 1);
}

sub loggedDebug {
	if ($Log::Message::Simple::log_debug) {
		Log::Message::Simple::debug('' . (substr `date -u +'%F %H:%M:%S %Z'`, 0, -1) . ' - ' . $_[0], 1);
	}
}

## /Logger ##



## Files ##

## 
 # Give the names of children directory of a given directory (immediately under)
 # 
 # @return Array Array of names
 ##
sub getChildrenDirectories
{
	#TODO: Flag to enable/disable the finding of dot folders (such as ".bidule")
	my @directories = ();
	opendir(DIR, $_[0]) or die 'getChildrenDirectories(): Failed to open "' . $_[0] . '"';
	while (defined($file = readdir(DIR))) {
		# next if ($file =~ m/^\./);
		next if ($file eq '.');
		next if ($file eq '..');
		next if !-d $_[0] . '/' . $file;
		push(@directories, $file);
	}
	closedir(DIR);
	return @directories;
}

## 
 # Give the names of children files of a given directory (immediately under)
 # 
 # @return Array Array of names
 ##
sub getChildrenFiles
{
	#TODO: Flag to enable/disable the finding of dot files (such as ".machin")
	my @files = ();
	opendir(DIR, $_[0]) or die 'getChildrenFiles(): Failed to open "' . $_[0] . '"';
	while (defined($file = readdir(DIR))) {
		# next if ($file =~ m/^\./);
		next if !-f $_[0] . '/' . $file;
		push(@files, $file);
	}
	closedir(DIR);
	return @files;
}

## 
 # Tells if a directory is empty or not
 # 
 # @param String	Path of directory to check
 # 
 # @return integer	1 if directory is empty, 0 otherwise
 ##
sub dirIsEmpty($)
{
	my $directory = shift;
	if (-d $directory) {
		$findCommand = 'find "' . $directory . '" -type f | wc -l';
		if (`$findCommand` == 0) { # Directory is empty
			return 1;
		}
		else { # Directory is NOT empty
			return 0;
		}
	}
	else { # Is NOT a directory
		return 0;
	}
}

## /Files ##



## Strings ##

## 
 # Trim a string
 # 
 # @return String	Trimmed string
 ##
sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

## /Strings ##


## External Storage ##

## 
 # List backups (dates of dailybackups) actually present on external storage
 # 
 # @return Array Array of dates
 ##
sub listBackupsOnExternalStorage
{
	loggedDebug '--- listBackupsOnExternalStorage() ---';
	
	my $ftpClient_authCommandPart = '';
	if ($externalStorage->{'user'}) {
		$ftpClient_authCommandPart = ' -u "' . $externalStorage->{'user'} . '","' . $externalStorage->{'password'} . '"';
	}
	my @files = ();
	open FH, $externalStorage->{'ftpClient'} . ' -e "cd \"' . $externalStorage->{'path'} . '\"; cls; exit;" -p ' . $externalStorage->{'port'} . $ftpClient_authCommandPart . ' ' . $externalStorage->{'host'} . ' |' or die 'Failed to connect to FTP server "' . $externalStorage->{'host'} . ':' . $externalStorage->{'port'} . '"';
	while (<FH>) {
		if ($_ =~ m/^([0-9]{4})-([0-1][0-9])-([0-3][0-9])\/?$/) {
			push(@files, (substr $_, 0, 10));
		}
	}
	close FH;
	
	loggedDebug '--- /listBackupsOnExternalStorage() ---';
	return @files;
}

## 
 # Delete a given dailybackups from external storage
 # 
 # @param string $dateToDelete	Date of backup to delete
 ##
sub deleteBackupOnExternalStorage
{
	my $dateToDelete = $_[0];
	
	loggedDebug '--- deleteBackupOnExternalStorage(' . $dateToDelete . ') ---';
	
	if ($dateToDelete == undef) {
		die 'deleteBackupOnExternalStorage() requires at least one argument ("dateToDelete")';
	}
	
	executeCommandOnExternalStorage('rm -r \"' . $dateToDelete . '\"');
	
	loggedDebug '--- /deleteBackupOnExternalStorage(' . $dateToDelete . ') ---';
}

## 
 # Remove backups that are too old
 # 
 # @param integer $maxAge				Age in days at which point a backup is said too old
 # @param string $baseDateForComparison	(Optional) Date to compare backups to, defaults to current date
 ##
sub cleanTooOldBackups {
	my ($maxAge, $baseDateForComparison) = @_;
	
	loggedDebug '--- cleanOldBackups(' . $maxAge . ', $baseDateForComparison) ---';
	
	if ($maxAge == undef) {
		die 'cleanTooOldBackups() requires at least one argument ("maxAge")';
	}
	if ($baseDateForComparison == undef) {
		$baseDateForComparison = Time::Piece::localtime()
	}
	else {
		$baseDateForComparison= Time::Piece->strptime($baseDateForComparison, '%Y-%m-%d %H:%M:%S');
	}
	
	loggedDebug '$maxAge = ' . $maxAge;
	loggedDebug '$baseDateForComparison = ' . $baseDateForComparison;
	
	loggedDebug 'Will compare to ' . $baseDateForComparison->datetime . ' (' . $baseDateForComparison->epoch . ')';
	@pastBackups = listBackupsOnExternalStorage();
	loggedDebug 'List of found backups';
	foreach (@pastBackups) {
		loggedDebug 'Iteration on "' . $_ . '"';
		$currentBackupedDay = Time::Piece->strptime($_, "%Y-%m-%d");
		loggedDebug "\t" . '$currentBackupedDay->datetime = ' . $currentBackupedDay->datetime;
		loggedDebug "\t" . '$currentBackupedDay->epoch = ' . $currentBackupedDay->epoch;
		$diff = $baseDateForComparison - $currentBackupedDay;
		
		loggedDebug "\t" . int($diff->days) . ' (' . $diff->days . ') days between ' . $baseDateForComparison->datetime . ' and ' . $currentBackupedDay->datetime;
		
		if (int($diff->days) >= $maxAge) {
			loggedMsg "\t" . $currentBackupedDay->datetime . ' is too old';
			deleteBackupOnExternalStorage($_);
		}
		
		loggedDebug '--';
	}
	loggedDebug '/List of found backups';
	loggedDebug '--- /cleanOldBackups(' . $maxAge . ', $baseDateForComparison) ---';
}

sub executeCommandOnExternalStorage
{
	my ($commandToExecute) = @_;
	
	loggedDebug '--- executeCommandOnExternalStorage(' . $commandToExecute . ') ---';
	
	$commandToExecute = trim $commandToExecute;
	if ((substr $commandToExecute, -1) ne ';') { # If no tailing ";"
		$commandToExecute = $commandToExecute . ';'; # Add it
	}
	
	$commandToExecute = 'cd \"' . $externalStorage->{'path'} . '\"; ' . $commandToExecute . ' exit;';
	
	loggedDebug 'Following command will be sent to LFTP: ' . $commandToExecute;
	
	my $ftpClient_authCommandPart = '';
	if ($externalStorage->{'user'}) {
		$ftpClient_authCommandPart = ' -u "' . $externalStorage->{'user'} . '","' . $externalStorage->{'password'} . '"';
	}
	
	my $output = '';
	open FH, $externalStorage->{'ftpClient'} . ' -e "' . $commandToExecute . '" -p ' . $externalStorage->{'port'} . $ftpClient_authCommandPart . ' ' . $externalStorage->{'host'} . ' |' or die 'Failed to connect to FTP server "' . $externalStorage->{'host'} . ':' . $externalStorage->{'port'} . '"';
	while (<FH>) {
		$output .= $_;
	}
	close FH;
	
	loggedDebug '--- /executeCommandOnExternalStorage(' . $commandToExecute . ') ---';
	
	return substr $output, 0, -1;
}

## 
 # Send backups to external storage
 # 
 # @param string $file	File to send
 ##
sub sendFileToExternalStorage
{
	my ($file) = @_;
	
	loggedDebug '--- sendFileToExternalStorage("' . $file . '") ---';
	
	if (!-f $file) {
		loggedDebug 'File "' . $file . '" doesn\'t exists: will return 0;';
		loggedDebug '--- /sendFileToExternalStorage("' . $file . '") ---';
		return 0;
	}
	else {
		my $relativePath = (substr $file, (length $workingBasePath));
		loggedDebug '$relativePath = ' . $relativePath;
		
		my $executeCommandOutput = executeCommandOnExternalStorage('lcd "' . $workingBasePath . '"; mput -c -d -E -O "' . $externalStorage->{'path'} . '" "' . $relativePath . '"');
		loggedDebug '$executeCommandOutput = ' . $executeCommandOutput;
		loggedMsg 'File "' . $file . '" sent to external storage at "' . $externalStorage->{'path'} . $relativePath . '"';
		
		loggedDebug '--- /sendFileToExternalStorage("' . $file . '") ---';
	}
}

## /External Storage ##


## Service: MySQL ##

## 
 # Backup a MySQL server by dumping it's MySQL databases
 # 
 # @param Hash $service	Infos on MySQL service to backup
 # 
 # @return integer	1 on success, 0 on (any) error
 ##
sub backupMysql
{
	my $service = $_[0];
	
	loggedDebug '--- backupMysql($service) ---';
	
	if ($service->{'type'} ne SERVICE_TYPE_MYSQL) {
		loggedError 'Given service is not of expected "' . SERVICE_TYPE_MYSQL . '" type (is "' . $service->{'type'} . '"): can\'t continue';
		return 0;
	}
	
	# Create the MySQL-WorkingPath:
	system('mkdir -p "' . $backupedDayWorkingPath . $service->{'subdir'} . '"');
	
	my @databasesToDump = ();
	open FH, $service->{'options'}{'mysqlclientfilepath'} . ' --host=' . $service->{'options'}{'host'} . ' --port=' . $service->{'options'}{'port'} . ' --user=' . $service->{'options'}{'user'} . ' --password=' . $service->{'options'}{'password'} . ' --skip-auto-rehash --batch --exec="SHOW DATABASES;" |  tail -n +2 |' or die 'Failed to fetch databases list';
	while (<FH>) {
		push(@databasesToDump, (substr $_, 0, -1));
	}
	close FH;
	
	
	my $currentDumpedDatabaseFilepath;
	foreach (@databasesToDump) {
		$currentDumpedDatabaseFilepath = service_mysql_dumpDatabase($service, $_);
		loggedDebug 'Dumped into: "' . $currentDumpedDatabaseFilepath . '"';
		sendFileToExternalStorage($currentDumpedDatabaseFilepath);
		loggedDebug 'File sent';
	}
	
	loggedDebug '--- /backupMysql($service) ---';
	
	return dirIsEmpty($backupedDayWorkingPath . $service->{'subdir'});
}

## 
 # Dump and compress a MySQL database
 # 
 # @param string $service		Infos on MySQL service to use
 # @param string $databaseName	Name of database to dump
 # 
 # @return string Absolute path of the compressed database
 ##
sub service_mysql_dumpDatabase
{
	my ($service, $databaseName) = @_;
	
	loggedDebug '--- service_mysql_dumpDatabase($service, ' . $databaseName . ') ---';
	loggedDebug '$databaseName = "' . $databaseName . '"';
	
	my $compressedDatabaseFilePath = $backupedDayWorkingPath . $service->{'subdir'} . $databaseName . '.sql' . $service->{'options'}{'compressFileExtension'};
	
	loggedMsg 'Dumping "' . $databaseName . '" database into "' . $compressedDatabaseFilePath . '"';
	
	system($service->{'options'}{'mysqldumpfilepath'}
			. ' --host=' . $service->{'options'}{'host'} . ' --port=' . $service->{'options'}{'port'} . ' --user=' . $service->{'options'}{'user'} . ' --password=' . $service->{'options'}{'password'}
			. ' --single-transaction'
			. ' ' . $databaseName
		. ' | sed \'1 i\-- \\
-- Some dump-restoration useful settings:\\
-- \\
SET FOREIGN_KEY_CHECKS=0; \\
SET SQL_LOG_BIN=0; \\
SET UNIQUE_CHECKS=0; \\
\\
\''
		. ' | ' . $service->{'options'}{'compressMethod'}
		. ' > "' . $compressedDatabaseFilePath . '"');
	
	loggedDebug '--- /service_mysql_dumpDatabase($service, ' . $databaseName . ') ---';
	
	return $compressedDatabaseFilePath;
}

## /Service: MySQL ##


## Service: File System ##

## 
 # Backup FS files
 # 
 # @param Hash $service	Infos on FS service to backup
 # 
 # @return integer	1 on success, 0 on (any) error
 ##
sub backupFs
{
	my $service = $_[0];
	
	loggedDebug '--- backupFs($service) ---';
	
	if ($service->{'type'} ne SERVICE_TYPE_FILESYSTEM) {
		loggedError 'Given service is not of expected "' . SERVICE_TYPE_FILESYSTEM . '" type (is "' . $service->{'type'} . '"): can\'t continue';
		return 0;
	}
	
	# Create the FS-WorkingPath:
	system('mkdir -p "' . $backupedDayWorkingPath . $service->{'subdir'} . '"');
	
	my $currentPathToBackup;
	my $currentCompressedDirectory;
	
	loggedDebug 'List of path to backup';
	foreach (@{ $service->{'options'}{'pathsToBackup'} }) {
		$currentPathToBackup = $_;
		if ($currentPathToBackup ne '') {
			loggedDebug 'Iteration on "' . $currentPathToBackup . '"';
			service_fs_backupDir($service, $currentPathToBackup);
		}
		loggedDebug '--';
	}
	
	loggedDebug '--- /backupFs($service) ---';
	
	return dirIsEmpty($backupedDayWorkingPath . $service->{'subdir'});
}

## 
 # Backup a FS directory
 # Path can end with a "*", in this case, all subdirectories will be compressed apart (recursive call)
 # 
 # @param string $service				Infos on FS service to use
 # @param string $dirPath				Absolute path of directory to compress
 # @param boolean $childrenFilesOnly	(Optional) Only compress immediate files? Default is bool(false) where any child (directory or file) is compressed.
 ##
sub service_fs_backupDir
{
	my ($service, $dirPath, $childrenFilesOnly) = @_;
	
	loggedDebug '--- service_fs_backupDir($service, ' . $dirPath . ', ' . $childrenFilesOnly . ') ---';
	
	if ((substr $dirPath, -1) eq '*') { # Path ending with a "*": meaning we want to compress subdirectories apart
		loggedDebug '* found: need to list all directories';
		
		$dirPath = substr $dirPath, 0, -1; # Strip the "*"
		
		if (!-d $dirPath) {
			loggedError 'Directory "' . $dirPath . '" doesn\'t exists: won\'t try to browse it';
		}
		else {
			foreach (getChildrenDirectories($dirPath)) { # Process all directories of $dirPath
				loggedDebug 'Sub-Iteration on "' . $dirPath . $_ . '/"';
				
				loggedDebug 'Recursive call to service_fs_backupDir($service, "' . $dirPath . $_ . '/")';
				service_fs_backupDir($service, $dirPath . $_ . '/');
			}
			# Now, handle children files of $dirPath
			loggedDebug 'Recursive call to service_fs_backupDir($service, "' . $dirPath . '", 1)';
			service_fs_backupDir($service, $dirPath, 1);
		}
	}
	else {
		if (!-d $dirPath) {
			loggedError 'Directory "' . $dirPath . '" doesn\'t exists: won\'t try to compress it';
		}
		else {
			$currentCompressedDirectory = service_fs_compressDir($service, $dirPath, $childrenFilesOnly);
			if ($currentCompressedDirectory) {
				loggedDebug 'Compressed into: "' . $currentCompressedDirectory . '"';
				sendFileToExternalStorage($currentCompressedDirectory);
			}
			else {
				loggedError 'Failed to compress "' . $dirPath . '"';
			}
		}
	}
	
	loggedDebug '--- /service_fs_backupDir($service, ' . $dirPath . ', ' . $childrenFilesOnly . ') ---';
}

## 
 # Compress a FS directory
 # 
 # @param string $service				Infos on FS service to use
 # @param string $dirPath				Absolute path of directory to compress
 # @param boolean $childrenFilesOnly	(Optional) Only compress immediate files? Default is bool(false) where any child (directory or file) is compressed.
 # 
 # @return string Absolute path of the compressed directory
 ##
sub service_fs_compressDir
{
	my ($service, $dirPath, $childrenFilesOnly) = @_;
	
	loggedDebug '--- service_fs_compressDir($service, ' . $dirPath . ', ' . $childrenFilesOnly . ') ---';
	
	if (!-d $dirPath) {
		loggedDebug '--- /service_fs_compressDir($service, ' . $dirPath . ', ' . $childrenFilesOnly . ') ---';
		return 0;
	}
	else {
		# Place the compressed directory under $backupedDayWorkingPath/$service->{'subdir'}
		my $compressedDirFilePath = ${backupedDayWorkingPath} . $service->{'subdir'} . (substr $dirPath, 1, -1) . $service->{'options'}{'archiveFileExtension'} . $service->{'options'}{'compressFileExtension'};
		loggedDebug '$compressedDirFilePath = ' . $compressedDirFilePath;
		
		# Create the FS-WorkingPath:
		system('mkdir -p "' . File::Basename::dirname($compressedDirFilePath) . '"');
		
		my $archiveCommand = '';
		if ($childrenFilesOnly) {
			# Will use find to list all immediate children files of $dirPath: find <directoryToTar> -maxdepth 1 -type f | tar cv -T - > <directoryToTar>.tar
			# Won't use "--no-recursion" option of tar here because even if sub-directory aren't processed, they are created (as empty) in final .tar file
			$archiveCommand = 'find "' . (substr $dirPath, 1) . '" -maxdepth 1 -type f | ' . $service->{'options'}{'archiveMethod'} . ' -T -';
		}
		else {
			$archiveCommand = $service->{'options'}{'archiveMethod'} . ' -f - "' . (substr $dirPath, 1) . '"';
		}
		loggedMsg 'Compressing ' . ($childrenFilesOnly ? 'files of ' : '' ) . '"' . $dirPath . '" directory into "' . $compressedDirFilePath . '"';
		
		#BUGFIX: We're doing "cd /" before archiving to get rid of the "/bin/tar: Removing leading `/' from member names" (in french: "Suppression de « / » au début des noms des membres") informational message
		#		 Need to make sure both $compressedDirFilePath is an absolute path (starting with a "/")
		#		 Possible solution: use "--directory" tar option?
		my $compressCommand = 'cd / && ' . $archiveCommand . ' | ' . $service->{'options'}{'compressMethod'} . ' - > ' . $compressedDirFilePath;
		loggedDebug '$compressCommand = "' . $compressCommand . '"';
		system($compressCommand);
		
		loggedDebug '$compressedDirFilePath = "' . $compressedDirFilePath . '"';
		loggedDebug '--- /service_fs_compressDir($service, ' . $dirPath . ', ' . $childrenFilesOnly . ') ---';
		
		return $compressedDirFilePath;
	}
}
## /Service: File System ##


## Service: LDAP ##

## 
 # Dump MySQL databases
 # 
 # @param Hash $service	Infos on FS service to backup
 ##
sub backupLdap
{
	my $service = $_[0];
	
	loggedDebug '--- backupLdap($service) ---';
	
	if ($service->{'type'} ne SERVICE_TYPE_LDAP) {
		loggedError 'Given service is not of expected "' . SERVICE_TYPE_LDAP . '" type (is "' . $service->{'type'} . '"): can\'t continue';
		return 0;
	}
	
	# Create the LDAP-WorkingPath:
	system('mkdir -p "' . $backupedDayWorkingPath . $service->{'subdir'} . '"');
	
	my $currentDumpedDnTreeFilepath;
	foreach (@{ $service->{'options'}{'dnTreesToBackup'} }) {
		loggedDebug 'Iteration on DN "' . $_ . '"';
		$currentDumpedDnTreeFilepath = service_ldap_dumpDnTree($service, $_);
		loggedDebug 'Dumped into: "' . $currentDumpedDnTreeFilepath . '"';
		sendFileToExternalStorage($currentDumpedDnTreeFilepath);
		loggedDebug 'File sent';
	}
	
	loggedDebug '--- /backupLdap($service) ---';
	
	return dirIsEmpty($backupedDayWorkingPath . $service->{'subdir'});
}

## 
 # Dump and compress a DN tree into a LDIF file
 # 
 # @param Hash $service		Infos on FS service to backup
 # @param string $dnTree	DN of tree to dump
 # 
 # @return string Absolute path of the compressed LDIF file
 ##
sub service_ldap_dumpDnTree
{
	my ($service, $dnTree) = @_;
	
	loggedDebug '--- service_ldap_dumpDnTree($service, ' . $dnTree . ') ---';
	loggedDebug '$dnTree = "' . $dnTree . '"';
	
	my $compressedLdifFilePath = $backupedDayWorkingPath . $service->{'subdir'} . $dnTree . $service->{'options'}{'dumpFileExtension'} . $service->{'options'}{'compressFileExtension'};
	
	loggedMsg 'Dumping "' . $dnTree . '" tree into "' . $compressedLdifFilePath . '"';
	
	system($service->{'options'}{'slapcatFilepath'} 
			. ' -s "' . $dnTree . '"'
		. ' | ' . $service->{'options'}{'compressMethod'}
		. ' > "' . $compressedLdifFilePath . '"');
	
	loggedDebug '--- /service_ldap_dumpDnTree($service, ' . $dnTree . ') ---';
	
	return $compressedLdifFilePath;
}

## /Service: LDAP ##

##### /Functions #####



##### Process #####

# Prepare processes' run informations storage
my %serviceRuns = ();
while (my ($currentServiceType, $servicesOfCurrentType) = each(%$services)) { # For each type of services
	$serviceRuns->{$currentServiceType} = ();
	while (my ($currentServiceId, $currentServiceInfos) = each(%$servicesOfCurrentType)) { # For each services of that type ($currentServiceType)
		if ($currentServiceInfos->{'enabled'} == 1) { # If service is enabled
			$serviceRuns->{$currentServiceType}{$currentServiceId} = { # Mark it as:
				ran    => 0,		# Not run (yet)
				result => undef,	# Unknown result (yet)
			};
		}
	}
	if (! defined $serviceRuns->{$currentServiceType}) { # If no services were added for that type ($currentServiceType)
		delete $serviceRuns->{$currentServiceType}; # Remove (because it's useless)
	}
}
# /Prepare processes' run informations storage


$backupedDay_ts = Date::Parse::str2time(`date -u +'%Y-%m-%d 00:00:00 UTC'`);
$backupedDay = Date::Format::time2str("%Y-%m-%d", $backupedDay_ts);
$backupedDayWorkingPath = $workingBasePath . $backupedDay . '/';

# Start of script
my $backupStartTime = substr `date -u +'%F %H:%M:%S %Z'`, 0, -1;
loggedMsg 'Backup script for server "' . $backupedServerName . '" started on ' . $backupStartTime;

print "\n";
loggedMsg 'Will backup "' . $backupedDay . '"\'s datas into "' . $backupedDayWorkingPath . '" and send it to ftp://' . $externalStorage->{'user'} . '@' . $externalStorage->{'host'} . ':' . $externalStorage->{'port'} . $externalStorage->{'path'};
print "\n";

my $noErrors = undef;


# Backup MySQL
loggedDebug 'Will proceed with services of type "' . SERVICE_TYPE_MYSQL . '" (' . scalar(keys %{$services->{+SERVICE_TYPE_MYSQL}}) . ' service(s) in configuration)...';
while (my ($currentServiceId, $currentServiceInfos) = each (%{$services->{+SERVICE_TYPE_MYSQL}})) { # For each services of type SERVICE_TYPE_MYSQL
	loggedDebug "\t" . 'Iterating on Service "' . $currentServiceId . '" (enabled = ' . $currentServiceInfos->{'enabled'} . '; subdir = "' . $currentServiceInfos->{'subdir'} . '")';
	
	if ($currentServiceInfos->{'enabled'} == 1) {
		loggedMsg '--------------------------------------------------------------------------------';
		loggedMsg '- Backup MySQL service "' . $currentServiceId . '"';
		loggedMsg '----------';
		$serviceRuns->{+SERVICE_TYPE_MYSQL}{$currentServiceId}{'result'} = backupMysql($currentServiceInfos);
		$serviceRuns->{+SERVICE_TYPE_MYSQL}{$currentServiceId}{'ran'} = 1;
		loggedMsg '';
		if ($serviceRuns->{+SERVICE_TYPE_MYSQL}{$currentServiceId}{'result'} == 1) {
			loggedMsg 'Backup MySQL service "' . $currentServiceId . '" => OK';
			$noErrors = 1 unless defined $noErrors;
		}
		else {
			loggedError 'Backup MySQL service "' . $currentServiceId . '" => ERROR';
			$noErrors = 0;
		}
		loggedMsg '--------------------------------------------------------------------------------';
		
		
		print "\n";
		loggedMsg '';
		print "\n";
	}
	else {
		loggedDebug "\t" . 'Service "' . $currentServiceId . '" is disabled: skipping';
	}
}


# Backup LDAP
loggedDebug 'Will proceed with services of type "' . SERVICE_TYPE_LDAP . '" (' . scalar(keys %{$services->{+SERVICE_TYPE_LDAP}}) . ' service(s) in configuration)...';
while (my ($currentServiceId, $currentServiceInfos) = each (%{$services->{+SERVICE_TYPE_LDAP}})) { # For each services of type SERVICE_TYPE_LDAP
	loggedDebug "\t" . 'Iterating on Service "' . $currentServiceId . '" (enabled = ' . $currentServiceInfos->{'enabled'} . '; subdir = "' . $currentServiceInfos->{'subdir'} . '")';
	
	if ($currentServiceInfos->{'enabled'} == 1) {
		loggedMsg '--------------------------------------------------------------------------------';
		loggedMsg '- Backup LDAP service "' . $currentServiceId . '"';
		loggedMsg '----------';
		$serviceRuns->{+SERVICE_TYPE_LDAP}{$currentServiceId}{'result'} = backupLdap($currentServiceInfos);
		$serviceRuns->{+SERVICE_TYPE_LDAP}{$currentServiceId}{'ran'} = 1;
		loggedMsg '';
		if ($serviceRuns->{+SERVICE_TYPE_LDAP}{$currentServiceId}{'result'} == 1) {
			loggedMsg 'Backup LDAP service "' . $currentServiceId . '" => OK';
			$noErrors = 1 unless defined $noErrors;
		}
		else {
			loggedError 'Backup LDAP service "' . $currentServiceId . '" => ERROR';
			$noErrors = 0;
		}
		loggedMsg '--------------------------------------------------------------------------------';
		
		
		print "\n";
		loggedMsg '';
		print "\n";
	}
	else {
		loggedDebug "\t" . 'Service "' . $currentServiceId . '" is disabled: skipping';
	}
}


# Backup FS
loggedDebug 'Will proceed with services of type "' . SERVICE_TYPE_FILESYSTEM . '" (' . scalar(keys %{$services->{+SERVICE_TYPE_FILESYSTEM}}) . ' service(s) in configuration)...';
while (my ($currentServiceId, $currentServiceInfos) = each (%{$services->{+SERVICE_TYPE_FILESYSTEM}})) { # For each services of type SERVICE_TYPE_FILESYSTEM
	loggedDebug "\t" . 'Iterating on Service "' . $currentServiceId . '" (enabled = ' . $currentServiceInfos->{'enabled'} . '; subdir = "' . $currentServiceInfos->{'subdir'} . '")';
	
	if ($currentServiceInfos->{'enabled'} == 1) {
		loggedMsg '--------------------------------------------------------------------------------';
		loggedMsg '- Backup File System service "' . $currentServiceId . '"';
		loggedMsg '----------';
		$serviceRuns->{+SERVICE_TYPE_FILESYSTEM}{$currentServiceId}{'result'} = backupFs($currentServiceInfos);
		$serviceRuns->{+SERVICE_TYPE_FILESYSTEM}{$currentServiceId}{'ran'} = 1;
		loggedMsg '';
		if ($serviceRuns->{+SERVICE_TYPE_FILESYSTEM}{$currentServiceId}{'result'} == 1) {
			loggedMsg 'Backup File System service "' . $currentServiceId . '" => OK';
			$noErrors = 1 unless defined $noErrors;
		}
		else {
			loggedError 'Backup File System service "' . $currentServiceId . '" => ERROR';
			$noErrors = 0;
		}
		loggedMsg '--------------------------------------------------------------------------------';
		
		
		print "\n";
		loggedMsg '';
		print "\n";
	}
	else {
		loggedDebug "\t" . 'Service "' . $currentServiceId . '" is disabled: skipping';
	}
}


# Cleaning
if ($noErrors == 1 || $noErrors == undef) { # If no errors OR if nothing ran ($noErrors == undef)
	if ($noErrors == 1) {
		# Clean too old backups
		loggedMsg '--------------------------------------------------------------------------------';
		loggedMsg '- Removing old backups (more than ' . $externalStorage->{'numberOfDailyBackupToKeep'} . ' days)';
		loggedMsg '----------';
		cleanTooOldBackups($externalStorage->{'numberOfDailyBackupToKeep'});
		loggedMsg '--------------------------------------------------------------------------------';
		
		print "\n";
		loggedMsg '';
		print "\n";
	}
	
	# Remove $backupedDayWorkingPath directory
	loggedMsg '--------------------------------------------------------------------------------';
	loggedMsg '- Deleting temporary working path ("' . $backupedDayWorkingPath . '")';
	loggedMsg '----------';
	`rm -rf "$backupedDayWorkingPath"`;
	if ($? == 0) {
		loggedMsg '=> OK';
	}
	else {
		loggedError '=> NOK';
	}
	loggedMsg '--------------------------------------------------------------------------------';
}
else {
	loggedError 'There are still files in working path ("' . $backupedDayWorkingPath . '"): At least one backup went bad, no cleaning will be performed.';
	while (my ($currentServiceType, $servicesOfCurrentType) = each(%$serviceRuns)) { # For each type of services
		while (my ($currentServiceId, $currentServiceRunInfos) = each(%$servicesOfCurrentType)) { # For each services of that type ($currentServiceType)
			loggedDebug 'Service "' . $currentServiceId . '" (type "' . $currentServiceType . '") ' . ($currentServiceRunInfos->{'ran'} == 1 ? 'ran: ' . (defined $currentServiceRunInfos->{'result'} && $currentServiceRunInfos->{'result'} == 1 ? 'OK' : 'NOT OK') : 'not ran'); 
		}
	}
}
# /Cleaning


print "\n";
print "\n";

# End of script
my $backupEndTime = substr `date -u +'%F %H:%M:%S %Z'`, 0, -1;
$backupDuration = Date::Parse::str2time($backupEndTime) -  Date::Parse::str2time($backupStartTime);

loggedMsg 'Backup script for server "' . $backupedServerName . '" ended on ' . $backupEndTime . ' (' . $backupDuration . ' seconds)';
