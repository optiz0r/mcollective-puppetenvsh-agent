#!/opt/puppetlabs/puppet/bin/ruby

require "mcollective"

ddlfile = ARGV.shift

abort("Please specify an input DDL as argument") unless ddlfile

ddl = MCollective::DDL.new(File.basename(ddlfile, ".ddl"), :agent, false)
ddl.instance_eval(File.read(ddlfile))

  data = {
    "$schema" => "https://choria.io/schemas/mcorpc/ddl/v1/agent.json",
    "metadata" => ddl.meta,
    "actions" => [],
  }

ddl.actions.sort.each do |action|
  data["actions"] << ddl.action_interface(action)
end

puts JSON.pretty_generate(data)
