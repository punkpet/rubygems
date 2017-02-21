# frozen_string_literal: true
require "spec_helper"

RSpec.describe "Bundler.setup" do
  describe "with no arguments" do
    it "makes all groups available" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :group => :test
      G

      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        Bundler.setup

        require 'rack'
        puts RACK
      RUBY
      expect(err).to lack_errors
      expect(out).to eq("1.0.0")
    end
  end

  describe "when called with groups" do
    before(:each) do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "yard"
        gem "rack", :group => :test
      G
    end

    it "doesn't make all groups available" do
      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        Bundler.setup(:default)

        begin
          require 'rack'
        rescue LoadError
          puts "WIN"
        end
      RUBY
      expect(err).to lack_errors
      expect(out).to eq("WIN")
    end

    it "accepts string for group name" do
      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        Bundler.setup(:default, 'test')

        require 'rack'
        puts RACK
      RUBY
      expect(err).to lack_errors
      expect(out).to eq("1.0.0")
    end

    it "leaves all groups available if they were already" do
      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        Bundler.setup
        Bundler.setup(:default)

        require 'rack'
        puts RACK
      RUBY
      expect(err).to lack_errors
      expect(out).to eq("1.0.0")
    end

    it "leaves :default available if setup is called twice" do
      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        Bundler.setup(:default)
        Bundler.setup(:default, :test)

        begin
          require 'yard'
          puts "WIN"
        rescue LoadError
          puts "FAIL"
        end
      RUBY
      expect(err).to lack_errors
      expect(out).to match("WIN")
    end

    it "handles multiple non-additive invocations" do
      ruby <<-RUBY
        require 'bundler'
        Bundler.setup(:default, :test)
        Bundler.setup(:default)
        require 'rack'

        puts "FAIL"
      RUBY

      expect(err).to match("rack")
      expect(err).to match("LoadError")
      expect(out).not_to match("FAIL")
    end
  end

  context "load order" do
    it "puts loaded gems after -I and RUBYLIB" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      ENV["RUBYOPT"] = "-Idash_i_dir"
      ENV["RUBYLIB"] = "rubylib_dir"

      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        Bundler.setup
        puts $LOAD_PATH
      RUBY

      load_path = out.split("\n")
      rack_load_order = load_path.index {|path| path.include?("rack") }

      expect(err).to eq("")
      expect(load_path[1]).to include "dash_i_dir"
      expect(load_path[2]).to include "rubylib_dir"
      expect(rack_load_order).to be > 0
    end

    it "orders the load path correctly when there are dependencies" do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rails"
      G

      ruby <<-RUBY
        require 'rubygems'
        require 'bundler'
        Bundler.setup
        puts $LOAD_PATH
      RUBY

      load_path = out.split("\n") - [
        bundler_path.to_s,
        bundler_path.join("gems/bundler-#{Bundler::VERSION}/lib").to_s,
        tmp("rubygems/lib").to_s,
        root.join("../lib").expand_path.to_s,
      ]
      load_path.map! {|lp| lp.sub(/^#{system_gem_path}/, "") }

      expect(load_path).to start_with(
        "/gems/rails-2.3.2/lib",
        "/gems/activeresource-2.3.2/lib",
        "/gems/activerecord-2.3.2/lib",
        "/gems/actionpack-2.3.2/lib",
        "/gems/actionmailer-2.3.2/lib",
        "/gems/activesupport-2.3.2/lib",
        "/gems/rake-10.0.2/lib"
      )
    end
  end

  it "raises if the Gemfile was not yet installed" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    ruby <<-R
      require 'rubygems'
      require 'bundler'

      begin
        Bundler.setup
        puts "FAIL"
      rescue Bundler::GemNotFound
        puts "WIN"
      end
    R

    expect(out).to eq("WIN")
  end

  it "doesn't create a Gemfile.lock if the setup fails" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    ruby <<-R
      require 'rubygems'
      require 'bundler'

      Bundler.setup
    R

    expect(bundled_app("Gemfile.lock")).not_to exist
  end

  it "doesn't change the Gemfile.lock if the setup fails" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    lockfile = File.read(bundled_app("Gemfile.lock"))

    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      gem "nosuchgem", "10.0"
    G

    ruby <<-R
      require 'rubygems'
      require 'bundler'

      Bundler.setup
    R

    expect(File.read(bundled_app("Gemfile.lock"))).to eq(lockfile)
  end

  it "makes a Gemfile.lock if setup succeeds" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    File.read(bundled_app("Gemfile.lock"))

    FileUtils.rm(bundled_app("Gemfile.lock"))

    run "1"
    expect(bundled_app("Gemfile.lock")).to exist
  end

  it "uses BUNDLE_GEMFILE to locate the gemfile if present" do
    gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    gemfile bundled_app("4realz"), <<-G
      source "file://#{gem_repo1}"
      gem "activesupport", "2.3.5"
    G

    ENV["BUNDLE_GEMFILE"] = bundled_app("4realz").to_s
    bundle :install

    expect(the_bundle).to include_gems "activesupport 2.3.5"
  end

  it "prioritizes gems in BUNDLE_PATH over gems in GEM_HOME" do
    ENV["BUNDLE_PATH"] = bundled_app(".bundle").to_s
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack", "1.0.0"
    G

    build_gem "rack", "1.0", :to_system => true do |s|
      s.write "lib/rack.rb", "RACK = 'FAIL'"
    end

    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  describe "integrate with rubygems" do
    describe "by replacing #gem" do
      before :each do
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "rack", "0.9.1"
        G
      end

      it "replaces #gem but raises when the gem is missing" do
        run <<-R
          begin
            gem "activesupport"
            puts "FAIL"
          rescue LoadError
            puts "WIN"
          end
        R

        expect(out).to eq("WIN")
      end

      it "version_requirement is now deprecated in rubygems 1.4.0+ when gem is missing" do
        run <<-R
          begin
            gem "activesupport"
            puts "FAIL"
          rescue LoadError
            puts "WIN"
          end
        R

        expect(err).to lack_errors
      end

      it "replaces #gem but raises when the version is wrong" do
        run <<-R
          begin
            gem "rack", "1.0.0"
            puts "FAIL"
          rescue LoadError
            puts "WIN"
          end
        R

        expect(out).to eq("WIN")
      end

      it "version_requirement is now deprecated in rubygems 1.4.0+ when the version is wrong" do
        run <<-R
          begin
            gem "rack", "1.0.0"
            puts "FAIL"
          rescue LoadError
            puts "WIN"
          end
        R

        expect(err).to lack_errors
      end
    end

    describe "by hiding system gems" do
      before :each do
        system_gems "activesupport-2.3.5"
        install_gemfile <<-G
          source "file://#{gem_repo1}"
          gem "yard"
        G
      end

      it "removes system gems from Gem.source_index" do
        run "require 'yard'"
        expect(out).to eq("bundler-#{Bundler::VERSION}\nyard-1.0")
      end

      context "when the ruby stdlib is a substring of Gem.path" do
        it "does not reject the stdlib from $LOAD_PATH" do
          substring = "/" + $LOAD_PATH.find {|p| p =~ /vendor_ruby/ }.split("/")[2]
          run "puts 'worked!'", :env => { "GEM_PATH" => substring }
          expect(out).to eq("worked!")
        end
      end
    end
  end

  describe "with paths" do
    it "activates the gems in the path source" do
      system_gems "rack-1.0.0"

      build_lib "rack", "1.0.0" do |s|
        s.write "lib/rack.rb", "puts 'WIN'"
      end

      gemfile <<-G
        path "#{lib_path("rack-1.0.0")}"
        source "file://#{gem_repo1}"
        gem "rack"
      G

      run "require 'rack'"
      expect(out).to eq("WIN")
    end
  end

  describe "with git" do
    before do
      build_git "rack", "1.0.0"

      gemfile <<-G
        gem "rack", :git => "#{lib_path("rack-1.0.0")}"
      G
    end

    it "provides a useful exception when the git repo is not checked out yet" do
      run "1"
      expect(err).to match(/the git source #{lib_path('rack-1.0.0')} is not yet checked out. Please run `bundle install`/i)
    end

    it "does not hit the git binary if the lockfile is available and up to date" do
      bundle "install"

      break_git!

      ruby <<-R
        require 'rubygems'
        require 'bundler'

        begin
          Bundler.setup
          puts "WIN"
        rescue Exception => e
          puts "FAIL"
        end
      R

      expect(out).to eq("WIN")
    end

    it "provides a good exception if the lockfile is unavailable" do
      bundle "install"

      FileUtils.rm(bundled_app("Gemfile.lock"))

      break_git!

      ruby <<-R
        require "rubygems"
        require "bundler"

        begin
          Bundler.setup
          puts "FAIL"
        rescue Bundler::GitError => e
          puts e.message
        end
      R

      run "puts 'FAIL'"

      expect(err).not_to include "This is not the git you are looking for"
    end

    it "works even when the cache directory has been deleted" do
      bundle "install --path vendor/bundle"
      FileUtils.rm_rf vendored_gems("cache")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "does not randomly change the path when specifying --path and the bundle directory becomes read only" do
      bundle "install --path vendor/bundle"

      with_read_only("**/*") do
        expect(the_bundle).to include_gems "rack 1.0.0"
      end
    end

    it "finds git gem when default bundle path becomes read only" do
      bundle "install"

      with_read_only("#{Bundler.bundle_path}/**/*") do
        expect(the_bundle).to include_gems "rack 1.0.0"
      end
    end
  end

  describe "when specifying local override" do
    it "explodes if given path does not exist on runtime" do
      build_git "rack", "0.8"

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install
      expect(out).to match(/at #{lib_path('local-rack')}/)

      FileUtils.rm_rf(lib_path("local-rack"))
      run "require 'rack'"
      expect(err).to match(/Cannot use local override for rack-0.8 because #{Regexp.escape(lib_path('local-rack').to_s)} does not exist/)
    end

    it "explodes if branch is not given on runtime" do
      build_git "rack", "0.8"

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install
      expect(out).to match(/at #{lib_path('local-rack')}/)

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}"
      G

      run "require 'rack'"
      expect(err).to match(/because :branch is not specified in Gemfile/)
    end

    it "explodes on different branches on runtime" do
      build_git "rack", "0.8"

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "master"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      bundle :install
      expect(out).to match(/at #{lib_path('local-rack')}/)

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :branch => "changed"
      G

      run "require 'rack'"
      expect(err).to match(/is using branch master but Gemfile specifies changed/)
    end

    it "explodes on refs with different branches on runtime" do
      build_git "rack", "0.8"

      FileUtils.cp_r("#{lib_path("rack-0.8")}/.", lib_path("local-rack"))

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :ref => "master", :branch => "master"
      G

      gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", :git => "#{lib_path("rack-0.8")}", :ref => "master", :branch => "nonexistant"
      G

      bundle %(config local.rack #{lib_path("local-rack")})
      run "require 'rack'"
      expect(err).to match(/is using branch master but Gemfile specifies nonexistant/)
    end
  end

  describe "when excluding groups" do
    it "doesn't change the resolve if --without is used" do
      install_gemfile <<-G, :without => :rails
        source "file://#{gem_repo1}"
        gem "activesupport"

        group :rails do
          gem "rails", "2.3.2"
        end
      G

      install_gems "activesupport-2.3.5"

      expect(the_bundle).to include_gems "activesupport 2.3.2", :groups => :default
    end

    it "remembers --without and does not bail on bare Bundler.setup" do
      install_gemfile <<-G, :without => :rails
        source "file://#{gem_repo1}"
        gem "activesupport"

        group :rails do
          gem "rails", "2.3.2"
        end
      G

      install_gems "activesupport-2.3.5"

      expect(the_bundle).to include_gems "activesupport 2.3.2"
    end

    it "remembers --without and does not include groups passed to Bundler.setup" do
      install_gemfile <<-G, :without => :rails
        source "file://#{gem_repo1}"
        gem "activesupport"

        group :rack do
          gem "rack"
        end

        group :rails do
          gem "rails", "2.3.2"
        end
      G

      expect(the_bundle).not_to include_gems "activesupport 2.3.2", :groups => :rack
      expect(the_bundle).to include_gems "rack 1.0.0", :groups => :rack
    end
  end

  # Unfortunately, gem_prelude does not record the information about
  # activated gems, so this test cannot work on 1.9 :(
  if RUBY_VERSION < "1.9"
    describe "preactivated gems" do
      it "raises an exception if a pre activated gem conflicts with the bundle" do
        system_gems "thin-1.0", "rack-1.0.0"
        build_gem "thin", "1.1", :to_system => true do |s|
          s.add_dependency "rack"
        end

        gemfile <<-G
          gem "thin", "1.0"
        G

        ruby <<-R
          require 'rubygems'
          gem "thin"
          require 'bundler'
          begin
            Bundler.setup
            puts "FAIL"
          rescue Gem::LoadError => e
            puts e.message
          end
        R

        expect(out).to eq("You have already activated thin 1.1, but your Gemfile requires thin 1.0. Prepending `bundle exec` to your command may solve this.")
      end

      it "version_requirement is now deprecated in rubygems 1.4.0+" do
        system_gems "thin-1.0", "rack-1.0.0"
        build_gem "thin", "1.1", :to_system => true do |s|
          s.add_dependency "rack"
        end

        gemfile <<-G
          gem "thin", "1.0"
        G

        ruby <<-R
          require 'rubygems'
          gem "thin"
          require 'bundler'
          begin
            Bundler.setup
            puts "FAIL"
          rescue Gem::LoadError => e
            puts e.message
          end
        R

        expect(err).to lack_errors
      end
    end
  end

  # Rubygems returns loaded_from as a string
  it "has loaded_from as a string on all specs" do
    build_git "foo"
    build_git "no-gemspec", :gemspec => false

    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
      gem "foo", :git => "#{lib_path("foo-1.0")}"
      gem "no-gemspec", "1.0", :git => "#{lib_path("no-gemspec-1.0")}"
    G

    run <<-R
      Gem.loaded_specs.each do |n, s|
        puts "FAIL" unless s.loaded_from.is_a?(String)
      end
    R

    expect(out).to be_empty
  end

  it "does not load all gemspecs", :rubygems => ">= 2.3" do
    install_gemfile! <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    run! <<-R
      File.open(File.join(Gem.dir, "specifications", "broken.gemspec"), "w") do |f|
        f.write <<-RUBY
# -*- encoding: utf-8 -*-
# stub: broken 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "broken"
  s.version = "1.0.0"
  raise "BROKEN GEMSPEC"
end
        RUBY
      end
    R

    run! <<-R
      puts "WIN"
    R

    expect(out).to eq("WIN")
  end

  it "ignores empty gem paths" do
    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "rack"
    G

    ENV["GEM_HOME"] = ""
    bundle %(exec ruby -e "require 'set'")

    expect(err).to lack_errors
  end

  it "should prepend gemspec require paths to $LOAD_PATH in order" do
    update_repo2 do
      build_gem("requirepaths") do |s|
        s.write("lib/rq.rb", "puts 'yay'")
        s.write("src/rq.rb", "puts 'nooo'")
        s.require_paths = %w(lib src)
      end
    end

    install_gemfile <<-G
      source "file://#{gem_repo2}"
      gem "requirepaths", :require => nil
    G

    run "require 'rq'"
    expect(out).to eq("yay")
  end

  it "should clean $LOAD_PATH properly" do
    gem_name = "very_simple_binary"
    full_gem_name = gem_name + "-1.0"
    ext_dir = File.join(tmp "extenstions", full_gem_name)

    install_gem full_gem_name

    install_gemfile <<-G
      source "file://#{gem_repo1}"
    G

    ruby <<-R
      if Gem::Specification.method_defined? :extension_dir
        s = Gem::Specification.find_by_name '#{gem_name}'
        s.extension_dir = '#{ext_dir}'

        # Don't build extensions.
        s.class.send(:define_method, :build_extensions) { nil }
      end

      require 'bundler'
      gem '#{gem_name}'

      puts $LOAD_PATH.count {|path| path =~ /#{gem_name}/} >= 2

      Bundler.setup

      puts $LOAD_PATH.count {|path| path =~ /#{gem_name}/} == 0
    R

    expect(out).to eq("true\ntrue")
  end

  it "stubs out Gem.refresh so it does not reveal system gems" do
    system_gems "rack-1.0.0"

    install_gemfile <<-G
      source "file://#{gem_repo1}"
      gem "activesupport"
    G

    run <<-R
      puts Bundler.rubygems.find_name("rack").inspect
      Gem.refresh
      puts Bundler.rubygems.find_name("rack").inspect
    R

    expect(out).to eq("[]\n[]")
  end

  describe "when a vendored gem specification uses the :path option" do
    it "should resolve paths relative to the Gemfile" do
      path = bundled_app(File.join("vendor", "foo"))
      build_lib "foo", :path => path

      # If the .gemspec exists, then Bundler handles the path differently.
      # See Source::Path.load_spec_files for details.
      FileUtils.rm(File.join(path, "foo.gemspec"))

      install_gemfile <<-G
        gem 'foo', '1.2.3', :path => 'vendor/foo'
      G

      Dir.chdir(bundled_app.parent) do
        run <<-R, :env => { "BUNDLE_GEMFILE" => bundled_app("Gemfile") }
          require 'foo'
        R
      end
      expect(err).to lack_errors
    end

    it "should make sure the Bundler.root is really included in the path relative to the Gemfile" do
      relative_path = File.join("vendor", Dir.pwd[1..-1], "foo")
      absolute_path = bundled_app(relative_path)
      FileUtils.mkdir_p(absolute_path)
      build_lib "foo", :path => absolute_path

      # If the .gemspec exists, then Bundler handles the path differently.
      # See Source::Path.load_spec_files for details.
      FileUtils.rm(File.join(absolute_path, "foo.gemspec"))

      gemfile <<-G
        gem 'foo', '1.2.3', :path => '#{relative_path}'
      G

      bundle :install

      Dir.chdir(bundled_app.parent) do
        run <<-R, :env => { "BUNDLE_GEMFILE" => bundled_app("Gemfile") }
          require 'foo'
        R
      end

      expect(err).to lack_errors
    end
  end

  describe "with git gems that don't have gemspecs" do
    before :each do
      build_git "no-gemspec", :gemspec => false

      install_gemfile <<-G
        gem "no-gemspec", "1.0", :git => "#{lib_path("no-gemspec-1.0")}"
      G
    end

    it "loads the library via a virtual spec" do
      run <<-R
        require 'no-gemspec'
        puts NOGEMSPEC
      R

      expect(out).to eq("1.0")
    end
  end

  describe "with bundled and system gems" do
    before :each do
      system_gems "rack-1.0.0"

      install_gemfile <<-G
        source "file://#{gem_repo1}"

        gem "activesupport", "2.3.5"
      G
    end

    it "does not pull in system gems" do
      run <<-R
        require 'rubygems'

        begin;
          require 'rack'
        rescue LoadError
          puts 'WIN'
        end
      R

      expect(out).to eq("WIN")
    end

    it "provides a gem method" do
      run <<-R
        gem 'activesupport'
        require 'activesupport'
        puts ACTIVESUPPORT
      R

      expect(out).to eq("2.3.5")
    end

    it "raises an exception if gem is used to invoke a system gem not in the bundle" do
      run <<-R
        begin
          gem 'rack'
        rescue LoadError => e
          puts e.message
        end
      R

      expect(out).to eq("rack is not part of the bundle. Add it to Gemfile.")
    end

    it "sets GEM_HOME appropriately" do
      run "puts ENV['GEM_HOME']"
      expect(out).to eq(default_bundle_path.to_s)
    end
  end

  describe "with system gems in the bundle" do
    before :each do
      system_gems "rack-1.0.0"

      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack", "1.0.0"
        gem "activesupport", "2.3.5"
      G
    end

    it "sets GEM_PATH appropriately" do
      run "puts Gem.path"
      paths = out.split("\n")
      expect(paths).to include(system_gem_path.to_s)
      expect(paths).to include(default_bundle_path.to_s)
    end
  end

  describe "with a gemspec that requires other files" do
    before :each do
      build_git "bar", :gemspec => false do |s|
        s.write "lib/bar/version.rb", %(BAR_VERSION = '1.0')
        s.write "bar.gemspec", <<-G
          lib = File.expand_path('../lib/', __FILE__)
          $:.unshift lib unless $:.include?(lib)
          require 'bar/version'

          Gem::Specification.new do |s|
            s.name        = 'bar'
            s.version     = BAR_VERSION
            s.summary     = 'Bar'
            s.files       = Dir["lib/**/*.rb"]
            s.author      = 'no one'
          end
        G
      end

      gemfile <<-G
        gem "bar", :git => "#{lib_path("bar-1.0")}"
      G
    end

    it "evals each gemspec in the context of its parent directory" do
      bundle :install
      run "require 'bar'; puts BAR"
      expect(out).to eq("1.0")
    end

    it "error intelligently if the gemspec has a LoadError" do
      ref = update_git "bar", :gemspec => false do |s|
        s.write "bar.gemspec", "require 'foobarbaz'"
      end.ref_for("HEAD")
      bundle :install

      expect(out.lines.map(&:chomp)).to include(
        a_string_starting_with("[!] There was an error while loading `bar.gemspec`:"),
        RUBY_VERSION >= "1.9" ? a_string_starting_with("Does it try to require a relative path? That's been removed in Ruby 1.9.") : "",
        " #  from #{default_bundle_path "bundler", "gems", "bar-1.0-#{ref[0, 12]}", "bar.gemspec"}:1",
        " >  require 'foobarbaz'"
      )
    end

    it "evals each gemspec with a binding from the top level" do
      bundle "install"

      ruby <<-RUBY
        require 'bundler'
        def Bundler.require(path)
          raise "LOSE"
        end
        Bundler.load
      RUBY

      expect(err).to lack_errors
      expect(out).to eq("")
    end
  end

  describe "when Bundler is bundled" do
    it "doesn't blow up" do
      install_gemfile <<-G
        gem "bundler", :path => "#{File.expand_path("..", lib)}"
      G

      bundle %(exec ruby -e "require 'bundler'; Bundler.setup")
      expect(err).to lack_errors
    end
  end

  describe "when BUNDLED WITH" do
    def lock_with(bundler_version = nil)
      lock = <<-L
        GEM
          remote: file:#{gem_repo1}/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{generic_local_platform}

        DEPENDENCIES
          rack
      L

      if bundler_version
        lock += "\n        BUNDLED WITH\n           #{bundler_version}\n"
      end

      lock
    end

    before do
      install_gemfile <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G
    end

    context "is not present" do
      it "does not change the lock" do
        lockfile lock_with(nil)
        ruby "require 'bundler/setup'"
        lockfile_should_be lock_with(nil)
      end
    end

    context "is newer" do
      it "does not change the lock or warn" do
        lockfile lock_with(Bundler::VERSION.succ)
        ruby "require 'bundler/setup'"
        expect(out).to eq("")
        expect(err).to eq("")
        lockfile_should_be lock_with(Bundler::VERSION.succ)
      end
    end

    context "is older" do
      it "does not change the lock" do
        lockfile lock_with("1.10.1")
        ruby "require 'bundler/setup'"
        lockfile_should_be lock_with("1.10.1")
      end
    end
  end

  describe "when RUBY VERSION" do
    let(:ruby_version) { nil }

    def lock_with(ruby_version = nil)
      lock = <<-L
        GEM
          remote: file:#{gem_repo1}/
          specs:
            rack (1.0.0)

        PLATFORMS
          #{generic_local_platform}

        DEPENDENCIES
          rack
      L

      if ruby_version
        lock += "\n        RUBY VERSION\n           ruby #{ruby_version}\n"
      end

      lock += <<-L

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      lock
    end

    before do
      install_gemfile <<-G
        ruby ">= 0"
        source "file:#{gem_repo1}"
        gem "rack"
      G
      lockfile lock_with(ruby_version)
    end

    context "is not present" do
      it "does not change the lock" do
        expect { ruby! "require 'bundler/setup'" }.not_to change { lockfile }
      end
    end

    context "is newer" do
      let(:ruby_version) { "5.5.5" }
      it "does not change the lock or warn" do
        expect { ruby! "require 'bundler/setup'" }.not_to change { lockfile }
        expect(out).to eq("")
        expect(err).to eq("")
      end
    end

    context "is older" do
      let(:ruby_version) { "1.0.0" }
      it "does not change the lock" do
        expect { ruby! "require 'bundler/setup'" }.not_to change { lockfile }
      end
    end
  end

  describe "with gemified standard libraries" do
    it "does not load Psych", :ruby => "~> 2.2" do
      gemfile ""
      ruby <<-RUBY
        require 'bundler/setup'
        puts defined?(Psych::VERSION) ? Psych::VERSION : "undefined"
        require 'psych'
        puts Psych::VERSION
      RUBY
      pre_bundler, post_bundler = out.split("\n")
      expect(pre_bundler).to eq("undefined")
      expect(post_bundler).to match(/\d+\.\d+\.\d+/)
    end

    it "does not load openssl" do
      install_gemfile! ""
      ruby! <<-RUBY
        require "bundler/setup"
        puts defined?(OpenSSL) || "undefined"
        require "openssl"
        puts defined?(OpenSSL) || "undefined"
      RUBY
      expect(out).to eq("undefined\nconstant")
    end

    describe "default gem activation" do
      let(:code) { strip_whitespace(<<-RUBY) }
        require "rubygems"
        Gem::Specification.send(:alias_method, :bundler_spec_activate, :activate)
        Gem::Specification.send(:define_method, :activate) do
          warn '-' * 80
          warn "activating \#{full_name}"
          warn *caller
          warn '*' * 80
          bundler_spec_activate
        end
        require "bundler/setup"
        require "pp"
        loaded_specs = Gem.loaded_specs.dup
        loaded_specs.delete("bundler")
        pp loaded_specs
      RUBY

      it "activates no gems with -rbundler/setup" do
        install_gemfile! ""
        ruby!(code)
        expect(err).to eq("")
        expect(out).to eq("{}")
      end

      it "activates no gems with bundle exec" do
        install_gemfile! ""
        create_file("script.rb", code)
        bundle! "exec ruby ./script.rb"
        expect(err).to eq("")
        expect(out).to eq("{}")
      end

      it "activates no gems with bundle exec that is loaded" do
        install_gemfile! ""
        create_file("script.rb", "#!/usr/bin/env ruby\n\n#{code}")
        FileUtils.chmod(0o777, bundled_app("script.rb"))
        bundle! "exec ./script.rb"
        expect(err).to eq("")
        expect(out).to eq("{}")
      end
    end
  end

  describe "after setup" do
    it "allows calling #gem on random objects" do
      install_gemfile <<-G
        source "file:#{gem_repo1}"
        gem "rack"
      G
      ruby! <<-RUBY
        require "bundler/setup"
        Object.new.gem "rack"
        puts Gem.loaded_specs["rack"].full_name
      RUBY
      expect(out).to eq("rack-1.0.0")
    end
  end
end
