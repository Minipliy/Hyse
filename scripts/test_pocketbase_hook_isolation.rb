#!/usr/bin/env ruby

def assert(condition, message)
  raise message unless condition
end

hooks = Dir["pb_hooks/*.pb.js"].to_h { |path| [path, File.read(path)] }
foods = hooks.fetch("pb_hooks/global_food_submissions.pb.js")
language = hooks.fetch("pb_hooks/language_routes.pb.js")
recipes = hooks.fetch("pb_hooks/recipes.pb.js")

assert(foods.scan('require(`${__hooks}/global_food_submission_helpers.js`)').length == 3,
       "Every global-food route must load helpers inside its isolated callback")
assert(!foods.match?(/\bhyseRevision[A-Z]/), "Global-food routes must not capture module-level helper identifiers")
assert(!language.include?("hyseRequestHeader"), "The root route header helper must be callback-local")
assert(recipes.scan('require(`${__hooks}/recipe_helpers.js`)').length == 2,
       "Every global-recipe route must load helpers inside its isolated callback")
assert(!recipes.match?(/\bhyseRecipe(?:Text|Number|Snapshot|Unit|Key|Nutrients)\b/),
       "Global-recipe routes must not capture module-level helper identifiers")

closed_body_reads = hooks.select { |_path, source| source.include?("$apis.requestInfo(e.httpContext)") }.keys
assert(closed_body_reads.empty?, "Record hooks must read authRecord from Echo context, not consume the body: #{closed_body_reads.join(', ')}")

puts "PocketBase hook isolation contracts passed."
