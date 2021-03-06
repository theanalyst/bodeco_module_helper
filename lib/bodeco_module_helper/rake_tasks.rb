require 'puppetlabs_spec_helper/rake_tasks'

def io_popen(command)
  IO.popen(command) do |io|
    io.each do |line|
      print line
      yield line if block_given?
    end
  end
end

def validate(path)
  success = []
  failure = []

  Dir.glob(path).each do |file|
    yield file
    case $?.exitstatus
    when 0
      success.push file
    else
      failure.push file
    end
  end

  puts "Total: #{success.size + failure.size} files match #{path}"
  puts "Syntax OK: #{success.size}" unless success.size == 0
  unless failure.size == 0
    puts "Syntax FAILURE: #{failure.size}"
    puts failure.join(', ')
  end
end

begin
  require 'puppet_blacksmith/rake_tasks'

  # Don't tag with any prefix
  class Blacksmith::Git
    def tag!(version)
      exec_git "tag #{version}"
    end
  end
rescue LoadError
end

# Customize puppet-lint options
task :lint do
  PuppetLint.configuration.relative = true
  PuppetLint.configuration.disable_80chars
  PuppetLint.configuration.disable_arrow_alignment
  PuppetLint.configuration.disable_class_inherits_from_params_class
  PuppetLint.configuration.disable_class_parameter_defaults
  PuppetLint.configuration.ignore_paths = ['spec/**/*.pp', 'pkg/**/*.pp']
end

desc 'Validate puppet manifests, ERB templates, and Ruby files.'
task :validate do
  validate('{manifests,tests}/**/*.pp') do |manifest|
    system("puppet parser validate #{manifest}")
  end
  validate('lib/**/*.rb') do |ruby_lib|
    system("ruby -c #{ruby_lib} > /dev/null")
  end
  validate('templates/**/*.erb') do |template|
    system("erb -P -x -T '-' #{template} | ruby -c > /dev/null")
  end
end

desc 'Travis CI Tests'
task :travis do
  Rake::Task['validate'].execute
  Rake::Task['lint'].execute
  Rake::Task['spec'].execute
end

desc 'Vagrant VM power up and provision'
task :vagrant_up, [:manifest, :hostname] do |t, args|
  args.with_defaults(:manifest => 'init.pp', :hostname => '')
  Rake::Task['spec_prep'].execute

  env = "VAGRANT_MANIFEST='#{args[:manifest]}'"
  provision = false
  io_popen("export #{env}; vagrant up #{args[:hostname]}") do |line|
    provision = true if line =~ /is already running./
  end
  io_popen("export #{env}; vagrant provision #{args[:hostname]}") if provision
end

# Cleanup vagrant environment
desc 'Vagrant VM shutdown and fixtures cleanup'
task :vagrant_destroy do
  `vagrant destroy -f`
  Rake::Task['spec_clean'].execute
end
