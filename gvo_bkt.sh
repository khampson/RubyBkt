# Load the files in gvim in remote tabs, first starting a server in which to load them.

gvim --servername GV_RUBY_BKT
gvim --servername GV_RUBY_BKT --remote-tab bkt.rb \
					   bucket.log \
					   FileSet.rb \
					   testDriver.rb \
					   Compresser.rb \
					   readme.txt \
					   Utils.rb \
					   FileBucketSorter.rb \
					   testDriver.log



