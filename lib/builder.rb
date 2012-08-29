module Tracker

  require 'rest-client'
  require 'json'
  require 'open3'
  require 'base64'

  module Builder

    TRACKER_HOST = "tracker.deltacloud.org"

    TRACKER_URL = "http://#{TRACKER_HOST}/set?filter=status&filter_value=new"
    BUILD_URL = "http://#{TRACKER_HOST}/set/%s/build"

    USER = 'mfojtik@redhat.com'
    PASSWORD = ''

    def self.sets
      JSON::parse(RestClient.get(TRACKER_URL, { 'Accept' => 'application/json'}))
    end

    def self.pull_git_repo
      %x[cd repo && git pull]
    end

    def self.original_repo_dir
      File.join(File.dirname(__FILE__), '..', 'repo')
    end

    def self.build!(set_id)
      return if build_exists?(set_id)
      puts "[BUILD] Building http://#{TRACKER_HOST}/set/#{set_id}"
      build = Build.new(set_id)
      prepare_git_for_build(build)
      apply_set_patches(build)
      return cleanup_after(build) if build.error?
      install_dependencies(build)
      return cleanup_after(build) if build.error?
      run_tests(build)
      return cleanup_after(build) if build.error?
      cleanup_after(build)
      build
    end

    def self.result_dir
      File.join(File.dirname(__FILE__), '..', 'results')
    end

    def self.build_exists?(set_id)
      File.directory?(File.join(result_dir, set_id.to_s))
    end

    def self.cache_results!(build)
      build_result_dir = File.join(result_dir, build.build_id.to_s)
      FileUtils.mkdir_p(build_result_dir)
      build.results.each do |phase, result|
        File.open(File.join(build_result_dir, phase.to_s), 'w') { |f| f.write result }
      end
    end

    def self.upload_results!(build)
      RestClient.post(
        BUILD_URL % build.build_id,
        { :state => build.state }.merge(build.results),
        {
          :content_type => 'application/json',
          'Authorization' => "Basic #{basic_auth}"
        }
      )
    end

    def self.basic_auth
     Base64.encode64("#{USER}:#{PASSWORD}")
    end

    class Build
      attr_reader :build_id
      attr_accessor :state
      attr_reader :results

      def initialize(build_id)
        @build_id = build_id
        @results = {}
      end

      def error?
        state == :error
      end

      def build_dir
        File.join(File.dirname(__FILE__), '..', 'build', build_id.to_s)
      end

      def save(output)
        @results.merge!(state => output)
      end

    end

    def self.run_command(cmd, build)
      output, status = Open3.capture2e(cmd)
      build.save(output)
      status == 0
    end

    def self.prepare_git_for_build(build)
      cleanup_after(build)
      FileUtils.mkdir_p(build.build_dir)
      FileUtils.cp_r(original_repo_dir + '/.', build.build_dir)
    end

    def self.install_dependencies(build)
      build.state = :install
      puts "  - #{build.state}"
      unless run_command "cd #{build.build_dir}/server && bundle", build
        build.state = :error
      end
    end

    def self.apply_set_patches(build)
      build.state = :patches
      puts "  - #{build.state}"
      unless run_command "cd #{build.build_dir} && tracker download #{build.build_id} -b build", build
        build.state = :error
      end
    end

    def self.run_tests(build)
      build.state = :build
      puts "  - #{build.state}"
      unless run_command "cd #{build.build_dir}/server && rake test", build
        build.state = :failure
      else
        build.state = :success
      end
    end

    def self.cleanup_after(build)
      puts "  - cleanup"
      FileUtils.rm_rf(build.build_dir)
      build
    end

  end

end
