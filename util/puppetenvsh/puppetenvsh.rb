require "fileutils"
require "shellwords"

module MCollective
    module Util
        class Puppetenvsh

            attr_reader :puppetenvsh

            # Loads all configuration values from the config file
            # or sets sane defaults for those not provided
            def initialize
                config = Config.instance

                # Base directory which contains dynamic environments and the master repo
                @basedir = config.pluginconf.fetch('puppetenvsh.basedir', '/etc/puppet/environments')
                # Name of the directory under basedir which contains the master repo
                @master_repo_name = config.pluginconf.fetch('puppetenvsh.master_repo', '.puppet.git')
                # Name of the git remote to pull changes from when updating
                @upstream = config.pluginconf.fetch('puppetenvsh.upstream', 'origin')
                # Username for connecting to the remote
                @username = config.pluginconf.fetch('puppetenvsh.username', 'git')
                # Ignore local environments
                @local_environments = config.pluginconf.fetch('puppetenvsh.local_environments', 'live')
                # Whether to use librarian-puppet to manage modules
                @use_librarian = config.pluginconf.fetch('puppetenvsh.use_librarian', "false")
                # Paths for binaries used by this agent
                @git = config.pluginconf.fetch('puppetenvsh.git', 'git')
                @new_workdir = config.pluginconf.fetch('puppetenvsh.new_workdir', 'git-new-workdir')
                @librarian = config.pluginconf.fetch('puppetenvsh.librarian', 'librarian-puppet')

                # Some systems (rhel6) require a newer runtime for librarian-puppet
                # Source the ruby193 SCL environment if required
                @use_ruby193 = config.pluginconf.fetch('puppetenvsh.use_ruby193', "false")
                @ruby193_env = config.pluginconf.fetch('puppetenvsh.ruby193_env', '/opt/rh/ruby193/enable')

                # Convert string booleans to real booleans
                @use_librarian = !! (@use_librarian =~ /^1|true|yes/)
                @use_ruby193   = !! (@use_ruby193   =~ /^1|true|yes/)

                # Convert lists
                @local_environments = @local_environments.split(/,/)

                @ruby_env = ""
                if @use_ruby193
                    @ruby_env = "source #{@ruby193_env.shellescape}; "
                end

                # Fully qualified path to the master repo under basedir
                @master_repo_path = File.join(@basedir, @master_repo_name)
            end

            # Returns the list of existing environments under the basedir
            def list
                environments = []

                Dir.foreach(@basedir) { |item|
                    if item.start_with?('.') then
                        next
                    end
                    environments << item
                }

                environments
            end

            # Adds a new environment from a git branch name
            # 
            # * It's assumed existence of the branch has already been checked
            # * submodules will be updated if present
            # * librarian will be run if enabled
            def add(name)
                return false, "#{name} is a protected local environment" if @local_environments.include?(name)

                workdir = File.join(@basedir, name)
                command = "#{@new_workdir.shellescape} #{@master_repo_path.shellescape} #{workdir.shellescape} #{name.shellescape} >/dev/null 2>&1"
                output = ""
                failed = false

                output = `#{command}`
                failed = $?.exitstatus != 0

                submodule_success, submodule_output = submodule_update(name)
                failed ||= ! submodule_success
                output += submodule_output

                librarian_success, librarian_output = librarian_update(name)
                failed ||= ! librarian_success
                output += librarian_output

                return ! failed, output
            end

            # Updates an existing environment
            # 
            # * It's assumed existence of the environment has already been checked
            # * Submodules will be updated if present
            # * librarian will be run if enabeld
            def update(name)
                return false, "#{name} is a protected local environment" if @local_environments.include?(name)

                workdir = File.join(@basedir, name)
                command = "#{@git.shellescape} reset --hard #{@upstream.shellescape}/#{name.shellescape} 2>&1 >/dev/null"
                output = ""
                failed = false

                Dir.chdir(workdir) {
                    output = `#{command}`
                    failed = ! $?.exitstatus == 0

                    submodule_success, submodule_output = submodule_update(name)
                    failed ||= ! submodule_success
                    output += submodule_output

                    librarian_success, librarian_output = librarian_update(name)
                    failed ||= ! librarian_success
                    output += librarian_output
                }

                return ! failed, output
            end

            # Deletes an existing environment
            #
            # * It's assumed existence of the environment has already been checked
            def rm(name)
                return false, "#{name} is a protected local environment" if @local_environments.include?(name)

                workdir = File.join(@basedir, name)
                FileUtils.remove_entry_secure(workdir, true)

                return true
            end

            # Updates all environemnts
            #
            # * Missing environments will be added
            # * Existing environments will be updated
            # * Stale environments will be removed
            # * Submodules will be updated in all environments if present
            # * librarian will be run in all environments if enabled
            def update_all
                results = {
                    :added    => [],
                    :updated  => [],
                    :removed  => [],
                    :rejected => [],
                    :failed   => [],
                }
                messages = ""

                upstream_branches.each do |branch|
                    next if @local_environments.include?(branch)

                    environment = File.join(@basedir, branch)
                    if File.directory?(environment)
                        result, output = update(branch)

                        if result
                            results[:updated] << branch
                        else
                            results[:failed] << branch
                        end

                        messages += output
                    else
                        if validate_environment_name(branch)
                            result, output = add(branch)

                            if result
                                results[:added] << branch
                            else 
                                results[:failed] << branch
                            end

                            messages += output
                        else
                            results[:rejected] << branch
                            messages += "#{branch}: Rejected for not being a valid environment"
                        end
                    end
                end

                branches = upstream_branches
                list.each do |environment|
                    next if @local_environments.include?(environment)

                    if not branches.include?(environment)
                        rm(environment)
                        results[:removed] << environment
                    end
                end

                return results, messages
            end

            # Inits and updates any submodules in the environment
            def submodule_update(name)
                workdir = File.join(@basedir, name)
                command = "#{@git.shellescape} submodule init 2>&1 && #{@git.shellescape} submodule update 2>&1 >/dev/null"
                result = ""
                success = false

                Dir.chdir(workdir) {
                    result = `#{command}`
                    success = $?.exitstatus == 0
                }

                return success, result
            end

            # Uses librarian-puppet to update modules in an environment
            # 
            # Puppetfile.lock must be present to ensure the environment contains
            # the same versions used by the developer
            def librarian_update(name)
                workdir = File.join(@basedir, name)
                command = "#{@ruby_env}#{@librarian.shellescape} install --quiet 2>&1"
                result = ""
                success = false

                return true, "" unless @use_librarian
                return true, "" unless File.exists?(File.join(workdir, 'Puppetfile.lock'))

                Dir.chdir(workdir) {
                    result = `#{command} 2>&1`
                    success = $?.exitstatus == 0
                }

                return success, result
            end

            # Retrieve a list of branches from the upstream remote
            def upstream_branches
                command = "#{@git.shellescape} branch -r | grep #{@upstream.shellescape}'/*' | grep -v #{@upstream.shellescape}'/HEAD ->'"
                branches = []
                
                Dir.chdir(@master_repo_path) {
                    output = `#{command}`
                    branches = output.chomp.split(/\n/).map { |branch|
                        branch.strip.sub("#{@upstream}/", "")
                    }
                }

                return branches
            end

            # Validates that the environment name is valid for use as an environment
            #
            # * It must only consist of alpahnumeric characters and underscores
            # * It must refer to an existing branch in the upstream remote
            def validate_environment_name(name, require_branch=true)
                # Verify the name is valid as a puppet environment
                return false unless name.match(/^[a-zA-Z0-9_]+$/)

                # Verify the name corresponds with an existing git branch
                if require_branch
                    return false unless upstream_branches.include? name
                end

                return true
            end

            # Fetch the latest commits from the upstream repository
            #
            # * Stale remote references are pruned
            # * Submodules are updated recursively if the gitmodule commit is updated
            def fetch
                command = "#{@git.shellescape} fetch --prune --quiet #{@upstream.shellescape}"
                success = false

                Dir.chdir(@master_repo_path) {
                    `#{command}`
                    success = $?.exitstatus == 0
                }

                return success
            end

        end
    end
end
