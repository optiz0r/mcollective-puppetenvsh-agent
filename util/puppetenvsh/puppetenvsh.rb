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
                # Whether to use librarian-puppet to manage modules
                @use_librarian = config.pluginconf.fetch('puppetenvsh.use_librarian', false)
                # Paths for binaries used by this agent
                @git = config.pluginconf.fetch('puppetenvsh.git', 'git')
                @new_workdir = config.pluginconf.fetch('puppetenvsh.new_workdir', 'git-new-workdir')
                @librarian = config.pluginconf.fetch('puppetenvsh.librarian', 'librarian-puppet')

                # Some systems (rhel6) require a newer runtime for librarian-puppet
                # Source the ruby193 SCL environment if required
                @use_ruby193 = config.pluginconf.fetch('puppetenvsh.use_ruby193', false)
                @ruby193_env = config.pluginconf.fetch('puppetenvsh.ruby193_env', '/opt/rh/ruby193/enable')

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
                workdir = File.join(@basedir, name)
                command = "#{@new_workdir.shellescape} #{@master_repo_path.shellescape} #{workdir.shellescape} #{name.shellescape} 2>&1"
                output = ""
                returncode = 0

                Dir.chdir(workdir) {
                    output = `#{command}`
                    returncode = $?.exitstatus

                    submodule_returncode, submodule_output = submodule_update(name)
                    returncode |= submodule_returncode
                    output += submodule_output

                    librarian_returncode, librarian_output = librarian_update(name)
                    returncode |= librarian_returncode
                    output += librarian_output
                }

                return (returncode == 0), output
            end

            # Updates an existing environment
            # 
            # * It's assumed existence of the environment has already been checked
            # * Submodules will be updated if present
            # * librarian will be run if enabeld
            def update(name)
                workdir = File.join(@basedir, name)
                command = "#{@git.shellescape} reset --hard #{@upstream.shellescape}/#{name.shellescape}"
                output = ""
                returncode = 0

                Dir.chdir(workdir) {
                    output = `#{command}`
                    returncode = $?.exitstatus

                    submodule_returncode, submodule_output = submodule_update(name)
                    returncode |= submodule_returncode
                    output += submodule_output

                    librarian_returncode, librarian_output = librarian_update(name)
                    returncode |= librarian_returncode
                    output += librarian_output
                }

                return (returncode == 0), output
            end

            # Deletes an existing environment
            #
            # * It's assumed existence of the environment has already been checked
            def rm(name)
                workdir = File.join(@basedir, name)
                FileUtils.remove_entry_secure(workdir, true)
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
                    environment = File.join(@basedir, branch)
                    if Dir.exists?(environment)
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
                result = ""
                returncode = 0

                Dir.chdir(workdir) {
                    result = `#{@git.shellescape} submodule init 2>&1 && #{@git.shellescape} submodule update 2>&1`
                    returncode = $?.exitstatus
                }

                return (returncode == 0), result
            end

            # Uses librarian-puppet to update modules in an environment
            # 
            # Puppetfile.lock must be present to ensure the environment contains
            # the same versions used by the developer
            def librarian_update(name)
                if @use_librarian
                    workdir = File.join(@basedir, name)
                    command = "#{@ruby_env}#{@librarian.shellescape} install --verbose 2>&1"
                    result = ""
                    returncode = 0

                    return false, "Puppetfile.lock not present in environment #{name}; not invoking the librarian" unless
                        File.exists?(File.join(workdir, 'Puppetfile.lock'))

                    Dir.chdir(workdir) {
                        result = `#{command} 2>&1`
                        returncode = $?.exitstatus
                    }

                    return (returncode == 0), result
                end
            end

            # Retrieve a list of branches from the upstream remote
            def upstream_branches
                command = "#{@git.shellescape} branch --list --remotes #{@upstream.shellescape}'/*'"
                branches = []
                
                Dir.chdir(@master_repo_path) {
                    output = `#{command}`
                    branches = output.chomp.sub("#{@upstream}/", "").split(/n/)
                }

                return branches
            end

            # Validates that the environment name is valid for use as an environment
            #
            # * It must only consist of alpahnumeric characters and underscores
            # * It must refer to an existing branch in the upstream remote
            def validate_environment_name(name)
                # Verify the name is valid as a puppet environment
                return false unless name.match(/^[a-zA-Z0-9_]+$/)

                # Verify the name corresponds with an existing git branch
                return false unless upstream_branches.include? name

                return true
            end

            # Fetch the latest commits from the upstream repository
            #
            # * Stale remote references are pruned
            # * Submodules are updated recursively if the gitmodule commit is updated
            def fetch
                command = "#{@git.shellescape} fetch --prune --recurse-submodules=on-demand --quiet #{@upstream.shellescape}"
                returncode = 0

                Dir.chdir(@master_repo_path) {
                    `#{command}`
                    returncode = $?.exitstatus
                }

                return (returncode == 0)
            end

        end
    end
end
