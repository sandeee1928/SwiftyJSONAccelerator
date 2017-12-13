#!/usr/bin/env ruby

require 'xcodeproj'


def addfiles (direc, current_group, main_target)
    Dir.glob(direc) do |item|
        next if item == '.' or item == '.DS_Store'
        
        if File.directory?(item)
            new_folder = File.basename(item)
            created_group = current_group.new_group(new_folder)
            addfiles("#{item}/*", created_group, main_target)
            else
            i = current_group.new_file(item)
            if item.include? ".swift"
                main_target.add_file_references([i])
            end
        end
    end
end


first_arg, *the_rest = ARGV

project_file = first_arg
project = Xcodeproj::Project.open(project_file)


main_target = project.targets.first

new_group = project.main_group.find_subpath(File.join(main_target.name, 'Public/SchemaModels'), true)

the_rest.each do|a|
    addfiles("#{a}", new_group, main_target)
end

project.save(project_file)


