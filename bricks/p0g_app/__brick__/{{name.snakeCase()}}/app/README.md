# {{name.snakeCase()}}

The Flutter GUI. It holds no logic of its own: `lib/places/` says where a
service can run (Squadron's own place, or the process place where this
platform can launch one), and each panel in `lib/panels/` binds its
service's worker to the place the user picked.
