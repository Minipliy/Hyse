# Hyse shared links

Shared workout, recipe, and routine URLs open in the browser on `https://hyse.minipliy.net`:

- `/en/workout/<id>`
- `/de/training/<id>`
- `/en/recipe/<id>`
- `/de/rezept/<id>`
- `/en/routine/<id>`
- `/de/routine/<id>`

The Apple association file is served at
`https://hyse.minipliy.net/.well-known/apple-app-site-association` and
excludes HTTPS paths from automatic app opening. Each share page offers an
explicit app button.
Other website URLs stay in the browser. The email verification callback at
`/api/hyse/verify-email/<token>` still confirms the account on the server and
opens `hyseapp://login?verified=1`.

The workout landing page offers an App Store download button and an explicit
app button. The recipient can view only public workouts; private workouts do
not get a share link. Recipe links display approved global recipes or a
snapshot explicitly published by the owner. Private recipe links can be revoked
from the recipe detail screen.

Recipe sharing requires migration `1791000700_recipe_shares.js` and the
`recipe_share_routes.pb.js` / `recipe_shares.pb.js` hooks, plus the shared recipe
proxy rule in `deploy/Caddyfile`. The public record
contains only the displayed recipe snapshot. Personal recipe photos are synced
in the protected `user_recipes.image` field and copied to the unlisted share
record when the owner publishes or refreshes the link. Deleting a personal
recipe queues link revocation for the next successful connection.

Routine sharing uses migration `1791700300_routine_shares.js`, the
`routine_share_routes.pb.js` / `routine_shares.pb.js` hooks, and the shared
routine proxy rule in `deploy/Caddyfile`. An authenticated
owner publishes an unlisted snapshot of the routine's exercises, planned
sets, pauses, and notes, with an optional public photo. The page offers
`hyseapp://routine/<id>`; the iOS app can save an independent copy, including
the photo. Removing the link or deleting the source routine revokes public
access. Deletion while offline queues the revocation.

After deployment, check the association file and test links from Messages on a
device with Hyse installed and a device without it. Test a personal recipe with
and without a photo, an approved global recipe, and a revoked link.
