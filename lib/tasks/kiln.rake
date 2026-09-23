namespace :kiln do
  desc "Import a class's pieces from a CSV: bin/rails 'kiln:import[path/to/file.csv]'"
  task :import, [ :path ] => :environment do |_t, args|
    abort "usage: bin/rails 'kiln:import[path/to/file.csv]'" if args[:path].blank?

    created = Imports::PiecesCsv.new(args[:path]).run
    puts "Imported #{created} pieces."
  end
end
