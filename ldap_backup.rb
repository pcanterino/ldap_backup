#!/usr/bin/env ruby

# Keep this amount of backups (excluding the previously done backup)
# -1 for indefinite
$KEEP_BACKUPS = 7

# LDAP databases to backup
# (default: 1 / default database)
$BACKUP_DBS = [0, 1]

# Path to backup directory
$BACKUP_DIR = '/root/ldap_backup'

# Check if slapd is running before backup
# (use this if you installed this script on a cluster and you don't want to
# run backups on the inactive nodes)
$CHECK_SLAPD = false

# Create the backup directory if it does not exist
$CREATE_BACKUP_DIR = false

require 'date'

# Compose the name of a backup file by joining a prefix, a supplied timestamp
# and the database number (optional). The result is just the file name, you
# have to prefix the directory on your own.
def make_file_name(timestamp, db=nil)
    file_name = 'backup-'
    
    file_name += 'db' + db.to_s + '-' unless db.nil?
    
    file_name += timestamp + '.ldif'

    return file_name
end

# Remove old backup files in the backup directory. You have to specify the
# directory, the number of backups you want to keep, a file you explicitly want
# to keep (i.e. the most recent file) and optionally a database number.
# Only backup files belonging to the specified database number will be removed
# (if not, the ones of the default database will be removed).
def rotate_backups(dir, keep_backups, keep_file, db=nil)
    # Get all the files in the directory and remove everything from the list we
    # are not interested in

    files = Dir.entries(dir)
    
    files.keep_if { |f| f.start_with?('backup-') and f.end_with?('.ldif') }
    
    if db.nil?
        files.delete_if { |f| f.include?('-db') }    
    else
        files.keep_if { |f| f.include?('-db' + db.to_s + '-') }
    end
    
    files.delete(keep_file)
    
    files.sort!
    
    # Check if there are more files than we want to keep and remove the
    # outdated ones if necessary
    
    if files.size > keep_backups
        files_delete = files.slice(0, files.size - keep_backups)
    
        files_delete.each do |f|
            puts "Deleting #{f}..."
            
            begin
                File::unlink(dir + '/' + f)
            rescue SystemCallError => e
                puts "Could not delete file #{f}"
                puts e.message
            end
        end
    end
end

# Check if slapd is running

if $CHECK_SLAPD
    unless system('pidof slapd > /dev/null')
        puts "slapd not running"
        exit 1
    end
end

# Check if backup directory exists

if (defined?($BACKUP_DIR)).nil? or $BACKUP_DIR.empty?
    $BACKUP_DIR = '.'
end

unless Dir.exists?($BACKUP_DIR)
    if $CREATE_BACKUP_DIR
        puts "Creating directory #{$BACKUP_DIR}..."
        
        begin
            Dir.mkdir($BACKUP_DIR)
        rescue SystemCallError => e
            puts "Could not create directory #{$BACKUP_DIR}"
            puts e.message
            exit 1
        end
    else
        puts "Directory does not exist"
        exit 1
    end
end

# Backup

puts "Backing up..."

command = 'slapcat'

file_date = DateTime.now.strftime('%Y%m%d-%H%M%S')

unless (defined?($BACKUP_DBS)).nil? or $BACKUP_DBS.empty?
    $BACKUP_DBS.each do |db|
        backup_file = make_file_name(file_date, db)
        backup_file_path = $BACKUP_DIR + '/' + backup_file

        backup_command = command + ' -n '  + db.to_s + ' -l ' + backup_file_path
        
        puts "Backing up database #{db} to #{backup_file_path}"
        
        if system(backup_command)
            if $KEEP_BACKUPS >= 0
                puts "Rotating..."
        
                rotate_backups($BACKUP_DIR, $KEEP_BACKUPS, backup_file, db)
            end
        else
            puts "Backing up database #{db} failed with exit code " + $?.exitstatus.to_s
        end
    end
else
    backup_file = make_file_name(file_date)
    backup_file_path = $BACKUP_DIR + '/' + backup_file

    backup_command = command + ' -l ' + backup_file_path

    puts "Backing up default database to #{backup_file_path}"
    
    if system(backup_command)
        if $KEEP_BACKUPS >= 0
            puts "Rotating..."
        
            rotate_backups($BACKUP_DIR, $KEEP_BACKUPS, backup_file)
        end
    else
        puts "Backing up default database failed with exit code " + $?.exitstatus.to_s
    end
end
