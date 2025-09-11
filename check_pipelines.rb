project = Project.find(1)
puts "=== PIPELINE STATUS ==="
project.ci_pipelines.each do |pipeline|
  puts "Pipeline ID: #{pipeline.id}"
  puts "Status: #{pipeline.status}"
  puts "Ref: #{pipeline.ref}"
  puts "SHA: #{pipeline.sha}"
  puts "Created: #{pipeline.created_at}"
  puts "Jobs count: #{pipeline.builds.count}"
  pipeline.builds.each do |job|
    puts "  Job: #{job.name} - Status: #{job.status}"
    if job.failed?
      puts "    Failure reason: #{job.failure_reason}"
    end
  end
  puts "---"
end
