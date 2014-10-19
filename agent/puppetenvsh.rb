require 'mcollective/util/puppetenvsh/puppetenvsh'
module MCollective
    module Agent
        class Puppetenvsh<RPC::Agent
            activate_when do
                true
            end

            def startup_hook
                @puppetenvsh = Util::Puppetenvsh.new
            end

            action "list" do
                reply[:environments] = @puppetenvsh.list
            end

            action "add" do
                validate :environment, String

                @puppetenvsh.fetch

                reply.fail "Invalid dynamic environment name", 4 unless @puppetenvsh.validate_environment_name request[:environment]
                reply.fail "Environment already exists", 1 if @puppetenvsh.list.include?(request[:environment])
                
                return unless reply.statuscode == 0

                reply[:status], messages = @puppetenvsh.add request[:environment]
                reply.fail "Add failed: #{messages}", 4 unless reply[:status]
            end

            action "update" do
                validate :environment, String

                @puppetenvsh.fetch

                reply.fail "Invalid dynamic environment name", 4 unless @puppetenvsh.validate_environment_name request[:environment]
                reply.fail "Environment does not exist", 1 unless @puppetenvsh.list.include?(request[:environment])
                
                return unless reply.statuscode == 0

                reply[:status], messages = @puppetenvsh.update request[:environment]
                reply.fail "Update failed: #{messages}", 1 unless reply[:status]
            end

            action "rm" do
                validate :environment, String

                @puppetenvsh.fetch

                reply.fail "Invalid dynamic environment name", 4 unless @puppetenvsh.validate_environment_name request[:environment]
                reply.fail "Environment does not exist", 1 unless @puppetenvsh.list.include?(request[:environment])
                
                return unless reply.statuscode == 0

                @puppetenvsh.rm request[:environment]
            end

            action "update-all" do
                @puppetenvsh.fetch
                results, messages = @puppetenvsh.update_all

                reply[:added]    = results[:added]
                reply[:updated]  = results[:updated]
                reply[:removed]  = results[:removed]
                reply[:rejected] = results[:rejected]
                reply[:failed]   = results[:failed]
                reply[:messages] = messages
            end
        end
    end
end
