# RailsAdmin positioning security backport

`position.js` is the MIT-licensed jQuery UI 1.12.1 component distributed with
RailsAdmin 3.3.0, with the selector-only string handling from jQuery UI 1.13.0
backported for [CVE-2021-41184](https://github.com/jquery/jquery-ui/security/advisories/GHSA-gpqq-952q-5327).
The original license notice is retained in the file.

Sprockets resolves this application asset before RailsAdmin's vendored copy.
It keeps the existing widgets and positioning behavior while preventing an
HTML string in `position({ of: ... })` from creating executable elements.

Upstream fixed source:
https://github.com/jquery/jquery-ui/blob/1.13.0/ui/position.js

Remove this override when a RailsAdmin release ships a fixed positioning
component. Check the compiled admin asset, since the npm package constraints
do not describe the JavaScript actually vendored in the gem.
