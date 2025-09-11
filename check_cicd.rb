project = Project.find(1)
puts "Project: #{project.name}"
puts "CI/CD enabled: #{project.builds_enabled}"
puts "Shared runners: #{project.shared_runners_enabled}"
puts "Pipelines count: #{project.ci_pipelines.count}"
if project.ci_pipelines.any?
  puts "Latest pipeline: #{project.ci_pipelines.last.status}"
end
puts "CI/CD variables: #{project.variables.count}"
puts "Default branch: #{project.default_branch}"
puts "Repository empty: #{project.repository.empty?}"
