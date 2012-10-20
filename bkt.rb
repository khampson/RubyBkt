### Bucket
#
#	Main driver for the FileBucketSorter and Compresser code.
#	The purpose of this driver is to approximate a best-fit given a set of files and the space constraints
#	of a single-layer DVD. One or more filesets can be created and then optionally compressed in an (optionally)
#	password-protected archive.
#
#	The target size could be altered by creating and using a new constant in place of SINGLE_LAYER_DVD_BYTES.
#
#	Note: This was originally written on Windows with the intention of running only on Windows, and thus makes some Windows-specific
#		  assumptions about file paths and shell behavior, etc. Were cross-platform support required at the onset, some different implementation
#		  decisions would have been made at these Windows-specific points, likely through, among other things, more extensive use of
#		  the File and Dir classes to abstract the platform differences away, including the use of the PATH_SEPARATOR constant,
#		  realdirpath/realpath, getwd, etc; as well as the support for cmd-file equivalents on Unix-like platforms (likely bash scripts).
#
#		Written by Ken Hampson, hampsonk+github@gmail.com
#

# Built-in modules
require 'optparse'
require 'optparse/time'
require 'ostruct'
require 'pp'

# Custom modules
require 'Utils'
require 'FileBucketSorter'
require 'FileSet'
require 'Compresser'

$stdout.sync = true     # Autoflush stdout

# Set the thresholds for console and logfile logging
DEBUG       = Utils::DEBUG_OFF
LOG_DEBUG   = Utils::LOG_LOW

PROG_NAME = 'Bucket'
PROG_VER  = 'v2.0'

GB_IN_BYTES = 1024 * 1024 * 1024

# Discs say 4.7 GB, but in actuality, it's 4.3 GB and change. Manufacturers treat 1 KB as 1000 bytes instead
# of the true 1024, so the actual capacity is less. We'll round down to 4.3 -- from 4.384 -- to allow for a
# bit of extra room.
SINGLE_LAYER_DVD_BYTES = 4.3 * GB_IN_BYTES

# Many zip programs, 7-Zip included, do not do well with archives over 4 GB, so that's a good ceiling.
ZIP_MAX_SIZE = 4 * GB_IN_BYTES

LOGFILE_NAME = 'bucket.log'


class Optparse
    # Return a structure describing the options, created with the hash-esque OpenStruct class.
    def self.parse(args)
        # Defaults here
    		options = OpenStruct.new	# cmdline options container
            options.recurse = true      # recurse by default
    		
        opts = OptionParser.new do |opts|
            opts.banner = "Usage: bkt.rb [options]"
    			
            opts.separator ""
            opts.separator "Specific options:"
    			
            # Mandatory arguments
            opts.on("-path", "--path PATH",
                    "List of root PATHs (separated by '?') to search for files") do |path|

				# Separate the paths via a question mark since this isn't a valid character in Windows paths
				options.path = path.split('?')
            end

            opts.on("-root", "--root PATH",
                    "Destination path for archive") do |path|
                options.archroot = path
            end

            opts.separator ""
            opts.separator "Common options:"

			# Display the options
            opts.on_tail("-h", "--help", "Show this message") do
                puts opts
                exit
            end

            opts.on("-r", "--[no-]recurse", "[No] path recursion") do |r|
                options.recurse = r
            end
            
       		opts.on_tail("-v", "Show version") do
                puts "#{PROG_NAME} #{PROG_VER}"
                exit
            end

            opts.on("-pwd PWD", "--pwd PWD", "Password to use in archive") do |pwd|
                options.pwd = pwd
            end

            opts.on("-sets", "--sets N", Integer, "Generate N file sets") do |n|
                options.sets = n
            end
        end
    	
        opts.parse!(args)

        return options
    end  # parse()
end  # class Optparse


# Setup the log file (when log gets garbage-collected, log will be closed). Open for append if the file exists or create it if it doesn't.
log = File.open(LOGFILE_NAME, File::WRONLY | File::APPEND | File::CREAT)
log.puts "######################################################################################"
log.puts "#{PROG_NAME} #{PROG_VER}" 

Utils.printMux(log, "Creating Optparse object", DEBUG, LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)
options = Optparse.parse(ARGV)

Utils.printMux(log, "Done creating Optparse object", DEBUG, LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)
Utils.printMux(log, "Options:\n" + options.pretty_inspect(), DEBUG, LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)

# bail if no path was provided
if not options.path
	Utils.printMux(log, "No path specified. Exiting.", DEBUG, LOG_DEBUG, Utils::DEBUG_ALWAYS, Utils::LOG_LOW)
	exit(1)
end

Utils.printMux(log, "The following paths were specified:")
options.path.each {|item| Utils.printMux(log, item)}

Utils.printMux(log, "Creating FileBucketSorter object", DEBUG, LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)
buckets = FileBucketSorter.new(log, DEBUG, LOG_DEBUG)
Utils.printMux(log, "Done creating FileBucketSorter object", DEBUG, LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)

fileList = []

# Iterate over the supplied paths and glob the list of files from each
options.path.each do |dir|
    # Glob requires Unix-style paths even on Windows, so switch the slashes' direction
    dir.tr!('\\', '/')
    Utils.printMux(log, "Processing dir '#{dir}'")

    if (options.recurse)
        files = File.join(dir, "**", "*.*")
    else
        # non-recursive glob
        files = File.join(dir, "*.*")
    end

    Utils.printMux(log, "files: #{files}", DEBUG, LOG_DEBUG, Utils::DEBUG_MED, Utils::LOG_LOW)
    
    Dir.glob(files) do |name|
        Utils.printMux(log, "\tProcessing file '#{name}'")

        fileList << name
        buckets.add(name)
   end
end

Utils.printMux(log, "fileList:" + fileList.pretty_inspect(), DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
Utils.printMux(log, "buckets:\n" + buckets.dump(), DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

filesetSet = []
setNum = 0

# Now that the files have been bucket sorted, generate a set of files based on a best-fit from those buckets
until (buckets.empty?)
    setNum += 1
    bkts = buckets.buckets()
    Utils.printMux(log, "bkts:" + bkts.pretty_inspect(), DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    
    fileSet = buckets.fitFiles(SINGLE_LAYER_DVD_BYTES)

    Utils.printMux(log, "\nFileset ##{setNum}:\n" + fileSet.to_s(), DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    
    filesetSet << fileSet
    
    Utils.printMux(log, "Total size: #{buckets.totalSize} bytes (#{buckets.totalSize / GB_IN_BYTES.to_f()} GB)" + fileSet.to_s(), DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    Utils.printMux(log, "\nBuckets left\n" + buckets.dump(), DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

	# Bail if we're doing a specific number of sets and have reached that number
    break if (options.sets and setNum >= options.sets)
end

Utils.printMux(log, "File sets (#{filesetSet.size()}):\n", DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

# Now compress the resulting file set(s)
ctr = 1
filesetSet.each do |set|
    subset = FileSet.new(SINGLE_LAYER_DVD_BYTES, log, DEBUG, LOG_DEBUG)
    Utils.printMux(log, "\nSet\n" + set.pretty_inspect(), DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    
    # See if we need more than one set of archives
    if (set.size() >= ZIP_MAX_SIZE)
        Utils.printMux(log, "Fileset #{ctr} size exceeds the max zip size; splitting them up.")

		# Since the bucket sorter approximated a best fit for a single-layer DVD (~4.3 GB) and the zip max we're currently using is 4 GB,
		# splitting the files into two zip files will suffice. If this were to change, putting a loop here to split them in half iteratively
		# until under the zip max is probably advisable.

		# numToCopy is intentionally populated using integer division so dividing an odd number in half gets automatically truncated into
		# a whole number of files.
        numToCopy = set.numfiles() / 2
        Utils.printMux(log, "numToCopy = #{numToCopy}", DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
        
        numToCopy.times do |idx|
            file, size = set.pop()
            subset.add(file, size)
        end
        
        Utils.printMux(log, "set:\n#{set}", DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
        Utils.printMux(log, "subset:\n#{subset}", DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    end

	# Now build a set of sets based on the subset calculations above.
    sets = []
    sets << set
    sets << subset if (subset.numfiles() > 0)
    setctr = 1

    # Process each set
    sets.each do |s|
       # Create an archive for each set/subset
       archName = "#{options.archroot}\\arch#{ctr}-#{setctr}.zip"

       # Make sure to handle existing archives and pick up where we last left off
       while(1)
           break unless File.exists?(archName)
           ctr += 1
           archName = "#{options.archroot}\\arch#{ctr}-#{setctr}.zip"
           Utils.printMux(log, "Trying new archName '#{archName}'", DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
       end

       Utils.printMux(log, "Compressing fileset into '#{archName}'...")

       comp = Compresser.new(archName, s.fileNames, options.archroot, log, DEBUG, LOG_DEBUG)

       # set the password on the archive, if one was provided
       comp.pwd = options.pwd if options.pwd

       Utils.printMux(log, "comp:\n" + comp.pretty_inspect(), DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)
    
       out = comp.compress()
       Utils.printMux(log, "comp output:\n#{out}", DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

       setctr += 1
    end

    ctr += 1
end

# Determine a unique (i.e. non-existent) file name given a starting root string and extension
def getUniqueFileName(root, ext, start)
    ctr = start
    name = ""
    
    Utils.printMux(log, "getUniqueFileName> name = #{name}", DEBUG, LOG_DEBUG, Utils::DEBUG_LOW, Utils::LOG_LOW)

	# Iterate over different file-name permutations until one is found that does not exist
    while(1)
        name = root + ctr + ext
        break unless File.exist(name)
        ctr += 1
    end
    
    return name, ctr
end
