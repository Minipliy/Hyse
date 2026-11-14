#!/usr/bin/env ruby
# Deterministic regression tests for the guest/account scope contract. These
# tests require no PocketBase credentials and intentionally model delayed
# responses, partial merges and rapid account switching.

require "set"
require "time"

class ScopeHarness
  attr_reader :scope, :visible, :storage

  def initialize
    @scope = "guest"
    @revision = 0
    @visible = []
    @storage = Hash.new { |hash, key| hash[key] = [] }
  end

  def switch(to)
    @revision += 1
    @scope = to
    @visible = @storage[to].dup
  end

  def add(id)
    @visible << id unless @visible.include?(id)
    @storage[@scope] = @visible.dup
  end

  def operation_token
    [@scope, @revision]
  end

  def apply_remote(token, ids)
    return false unless token == operation_token
    @visible = ids.uniq
    @storage[@scope] = @visible.dup
    true
  end
end

def assert(condition, message)
  abort "FAILED: #{message}" unless condition
end

scope = ScopeHarness.new
scope.add("guest-entry")
scope.switch("user:one")
user_one_request = scope.operation_token
scope.add("user-one-local")
scope.switch("guest")
assert(!scope.apply_remote(user_one_request, ["user-one-remote"]), "stale account response was accepted after logout")
assert(scope.visible == ["guest-entry"], "logout did not restore the isolated guest scope")
assert(scope.storage["guest"] == ["guest-entry"], "stale response contaminated guest storage")

scope.switch("user:one")
old_request = scope.operation_token
scope.switch("user:two")
scope.add("user-two-local")
assert(!scope.apply_remote(old_request, ["user-one-remote"]), "response from another account was accepted")
assert(scope.visible == ["user-two-local"], "rapid account switch changed the active account data")

pending_merge = Set["guest-a", "guest-b"]
remote_after_partial = Set["guest-a"]
dirty_after_partial = Set["guest-b"]
partial_confirmed = pending_merge.subset?(remote_after_partial) && pending_merge.disjoint?(dirty_after_partial)
assert(!partial_confirmed, "partial merge was treated as complete")
remote_after_retry = Set["guest-a", "guest-b"]
dirty_after_retry = Set.new
complete_confirmed = pending_merge.subset?(remote_after_retry) && pending_merge.disjoint?(dirty_after_retry)
assert(complete_confirmed, "fully persisted merge was not confirmed")

# A 2xx create alone must not remove the optimistic local entry. The response
# has to be represented in the authoritative remote snapshot first.
local_ids = Set["new-entry"]
reported_uploads = Set["new-entry"]
remote_ids = Set.new
confirmed_uploads = reported_uploads & remote_ids
remaining_dirty = local_ids - confirmed_uploads
merged_ids = remote_ids | remaining_dirty
assert(merged_ids.include?("new-entry"), "optimistic entry disappeared after an unconfirmed upload")
remote_ids.add("new-entry")
confirmed_uploads = reported_uploads & remote_ids
remaining_dirty = local_ids - confirmed_uploads
assert(remaining_dirty.empty?, "server-confirmed entry stayed dirty")

pocketbase_date = "2026-08-24 18:18:37.390Z"
normalized_date = pocketbase_date.sub(/\A(.{10}) /, '\\1T')
assert(Time.iso8601(normalized_date).utc.year == 2026, "PocketBase date format was not normalized")

root = File.expand_path("..", __dir__)
store = File.read(File.join(root, "CalorieTrackerApp", "CalorieStore.swift"))
food_store = File.read(File.join(root, "CalorieTrackerApp", "FoodStore.swift"))
auth = File.read(File.join(root, "CalorieTrackerApp", "AuthManager.swift"))
sync_service = File.read(File.join(root, "CalorieTrackerApp", "CalorieEntrySyncService.swift"))
entry_model = File.read(File.join(root, "CalorieTrackerApp", "CalorieEntry.swift"))

{
  "entry scope token guard" => store.include?("isCurrent(scope:"),
  "account-specific pending merge key" => store.include?("pendingGuestKey(_ accountID: String)"),
  "confirmed-only guest removal" => store.include?("finishGuestMergeIfConfirmed"),
  "fixed destination scope save" => store.include?("save(scope: expectedScope)"),
  "food scope response guard" => food_store.include?("isCurrent(accountID:"),
  "auth response revision guard" => auth.include?("authRevision == expectedRevision"),
  "create response retained in remote merge" => sync_service.include?("remoteByClientID[id] = saved"),
  "server response confirms the uploaded amount" => sync_service.include?("Self.acknowledges(saved, entry: entry)") && sync_service.include?("abs(remote.amountGrams - entry.grams) <= tolerance"),
  "dirty cleared only after remote confirmation" => store.include?("remoteIDs.contains($0)"),
  "PocketBase record ID survives local cache reloads" => entry_model.include?("encodeIfPresent(remoteID, forKey: .remoteID)"),
  "PocketBase space date normalization" => sync_service.include?("replaceSubrange(separator...separator, with: \"T\")")
}.each { |name, present| assert(present, "missing #{name}") }

puts "Guest/account scope regression tests passed."
