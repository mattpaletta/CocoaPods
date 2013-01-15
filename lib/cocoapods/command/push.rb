require 'fileutils'
require 'active_support/core_ext/string/inflections'

module Pod
  class Command
    class Push < Command
      self.summary = 'Push new specifications to a spec-repo'

      self.description = <<-DESC
        Validates NAME.podspec or `*.podspec' in the current working dir, creates
        a directory and version folder for the pod in the local copy of 
        REPO (~/.cocoapods/[REPO]), copies the podspec file into the version directory,
        and finally it pushes REPO to its remote.
      DESC

      self.arguments = 'REPO [NAME.podspec]'

      def self.options
        [ ["--allow-warnings", "Allows to push if warnings are not evitable"],
          ["--local-only", "Does not perform the step of pushing REPO to its remote"] ].concat(super)
      end

      def initialize(argv)
        @allow_warnings = argv.flag?('allow-warnings')
        @local_only = argv.flag?('local-only')
        @repo = argv.shift_argument
        if @repo.nil?
          @repo = "master"
        elsif @repo.end_with? ".podspec"
          @podspec = @repo
          @repo = "master"
        else
          @podspec = argv.shift_argument
        end
        super
      end

      def validate!
        super
        help! "A spec-repo name is required." unless @repo
      end

      def run
        validate_podspec_files
        check_repo_status
        update_repo
        add_specs_to_repo
        push_repo unless @local_only
      end

      #--------------------------------------#

      private

      extend Executable
      executable :git

      def update_repo
        UI.puts "Updating the `#{@repo}' repo\n".yellow
        Dir.chdir(repo_dir) { UI.puts `git pull 2>&1` }
      end

      def push_repo
        UI.puts "\nPushing the `#{@repo}' repo\n".yellow
        Dir.chdir(repo_dir) { UI.puts `git push 2>&1` }
      end

      def repo_dir
        dir = config.repos_dir + @repo
        raise Informative, "`#{@repo}` repo not found" unless dir.exist?
        dir
      end

      # @todo: Add specs for staged and unstaged files.
      #
      def check_repo_status
        clean = Dir.chdir(repo_dir) { `git status --porcelain  2>&1` } == ''
        raise Informative, "The repo `#{@repo}` is not clean" unless clean
      end

      def podspec_files
        files = Pathname.glob(@podspec || "*.podspec")
        raise Informative, "Couldn't find any .podspec file in current directory" if files.empty?
        files
      end

      # @return [Integer] The number of the podspec files to push.
      #
      def count
        podspec_files.count
      end

      def validate_podspec_files
        UI.puts "\nValidating #{'spec'.pluralize(count)}".yellow
        podspec_files.each do |podspec|
          validator = Validator.new(podspec)
          begin
            validator.validate
          rescue Exception => e
            raise Informative, "The `#{podspec}` specification does not validate."
          end
          raise Informative, "The `#{podspec}` specification does not validate." unless validator.validated?
        end
      end

      # Commits the podspecs to the source, which should be a git repo.
      #
      # @note   The pre commit hook of the repo is skipped as the podspecs have
      #         already been linted.
      #
      # @todo   Raise if the source is not under git source control.
      #
      # @return [void]
      #
      def add_specs_to_repo
        UI.puts "\nAdding the #{'spec'.pluralize(count)} to the `#{@repo}' repo\n".yellow
        podspec_files.each do |spec_file|
          spec = Pod::Specification.from_file(spec_file)
          output_path = File.join(repo_dir, spec.name, spec.version.to_s)
          if Pathname.new(output_path).exist?
            message = "[Fix] #{spec}"
          elsif Pathname.new(File.join(repo_dir, spec.name)).exist?
            message = "[Update] #{spec}"
          else
            message = "[Add] #{spec}"
          end
          UI.puts " - #{message}"

          FileUtils.mkdir_p(output_path)
          FileUtils.cp(Pathname.new(spec.name+'.podspec'), output_path)
          Dir.chdir(repo_dir) do
            git!("add #{spec.name}")
            git!("commit --no-verify -m '#{message}'")
          end
        end
      end
    end
  end
end
