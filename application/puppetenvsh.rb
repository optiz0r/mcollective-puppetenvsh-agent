class MCollective::Application::Puppetenvsh<MCollective::Application
    description "Puppet dynamic environment manager (shell edition)"

    usage <<-END_OF_USAGE
mco puppetenvsh <ACTION> [ENVIRONMENT] [filters]
mco puppetenvsh <list|update-all> [filters]
mco puppetenvsh <add|update|rm> <ENVIRONMENT> [filters]
END_OF_USAGE

    def handle_message(action, message, *args)
        messages = {
            1 => "Please specify action",
            2 => "Action must be list, add, update, rm or update-all",
            3 => "Environment is required for add, update and rm actions",
            4 => "Unexpected extra arguments, aborting for safety",
        }
        send(action, messages[message] % args)
    end

    def post_option_parser(configuration)
        if ARGV.size < 1
            handle_message(:raise, 1)
        else
            generic_actions     = ['list','update-all']
            environment_actions = ['add','update','rm']
            
            if generic_actions.include?(ARGV[0])
                if ARGV.size > 1
                    handle_message(:raise, 4)
                else
                    configuration[:action] = ARGV.shift
                end
            elsif environment_actions.include?(ARGV[0])
                if ARGV.size < 2
                    handle_message(:raise, 3)
                elsif ARGV.size > 2
                    handle_message(:raise, 4)
                else
                    configuration[:action] = ARGV.shift
                    configuration[:environment] = ARGV.shift
                end
            else
                handle_message(:raise, 2)
            end
        end
    end

    def main
        puppetenvsh = rpcclient("puppetenvsh")
        puppetenvsh_result = puppetenvsh.send(configuration[:action], :environment => configuration[:environment])

        if !puppetenvsh_result.empty?
            sender_width = puppetenvsh_result.map{|s| s[:sender]}.map{|s| s.length}.max + 3
            pattern = "%%%ds: %%s" % sender_width

            puppetenvsh_result.each do |result|
                if result[:statuscode] == 0
                    if puppetenvsh.verbose
                        puts pattern % [result[:sender], JSON.dump(result[:data])]
                    else
                        case configuration[:action]
                        when 'list'
                            puts(pattern % [result[:sender], result[:data][:environments].join(' ')])
                        when 'update-all'
                            messages = result[:data].delete(:messages)
                            result[:data].each_key { |f|
                                if ! result[:data][f].kind_of?(Array) or result[:data][f].empty?
                                    result[:data].delete(f)
                                end
                            }
                            puts(pattern % [result[:sender], result[:data].map{|k,v| "#{k}: #{v.join(',')}"}.join(' ')])
                            puts("Messages: #{messages}")
                            puts
                        end
                    end
                else
                    puts(pattern % [result[:sender], result[:statusmsg]])
                end

                puts
            end

            printrpcstats :summarize => true, :caption => "puppetenvsh %s results" % configuration[:action]
            halt(puppetenvsh.stats)
        end
    end
end
