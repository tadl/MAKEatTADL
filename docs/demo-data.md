# Synthetic development data

The optional `demo:seed` task adds synthetic records for reviewing the staff
workspace. It is separate from the normal reference-data seeds in `db/seeds.rb`.
It preserves existing operational records and previously edited demo records.

Run it with the repository's Ruby version and bundle:

```sh
bin/rails demo:seed
```

The default is 300 demo jobs. To choose another target between 1 and 1,000:

```sh
COUNT=100 bin/rails demo:seed
```

The task only accepts the local PostgreSQL database named
`make_at_tadl_development` in development or `make_at_tadl_test` in tests, with
local disk attachment storage. It checks the connected database and server
address as well as the connection configuration, and refuses production.

## Default dataset

The 300-job dataset contains 240 print jobs and 60 scan jobs, all four request
categories, FDM and resin work, multiple-copy orders, model files, scan-result
files, photos, public replies, staff notes, and unread messages/notifications.
Historical records span roughly 18 months; active work is recent. Reminder
examples include information-request and pickup deadlines and missing anchors.

| Status | Jobs |
| --- | ---: |
| Pending | 24 |
| Information requested | 20 |
| Response received | 18 |
| Approved | 34 |
| In progress | 28 |
| Ready for pickup | 32 |
| Archived | 105 |
| Ongoing | 12 |
| Cancelled | 10 |
| Rejected | 7 |
| Abandoned | 10 |

It also adds 75 synthetic patrons, three non-administrator demo staff accounts,
12 library designs, six printers, and five active pickup locations:

| Location | Scanning | FDM | Resin |
| --- | --- | --- | --- |
| Demo Central Workshop | Yes | Yes | Yes |
| Demo East Branch | No | Yes | No |
| Demo North Branch | Yes | Yes | No |
| Demo South Workshop | No | Yes | Yes |
| Demo West Pickup | No | No | No |

The library has four entries each in Staff library, Assistive, and Fidget.
Without a supplied template, the task generates simple synthetic STL/3MF
geometry. Half of the new library entries have a generated sample photo; the
others exercise automatic mesh thumbnails. These shapes are interface fixtures,
not the functional objects suggested by the sample names.

## Use a local STL template

Supply a readable STL file of at most 20 MB to use its actual geometry for newly
created library entries and demo-job attachments:

```sh
MODEL_FILE="/absolute/path/example.stl" bin/rails demo:seed
```

The task uploads the template once and shares its blob. It does not copy the
file into the source repository. Existing demo jobs and existing library files
remain unchanged on an ordinary rerun; selecting a different template alone
does not replace them.

To explicitly replace model files throughout the local library, including
existing non-demo entries:

```sh
MODEL_FILE="/absolute/path/example.stl" REPLACE_LIBRARY_FILES=1 bin/rails demo:seed
```

This flag requires `MODEL_FILE`. It changes library attachments while keeping
each library record's name, collection, notes, and other metadata. Recognized
demo-generated photos are detached so automatic thumbnails can show the supplied
mesh; other uploaded photos remain. Existing job attachments retain the file
version they already use. This command also performs the normal additive seed
for the requested job count.

## Reruns and mail

Demo ownership is tracked with stable identifiers and audit markers. Rerunning
with the same count fills missing demo records without resetting edits or
duplicating messages and files. A lower count does not delete previously created
records. A reserved demo identifier already used by a non-demo record causes the
task to stop. Work is protected by a transaction and an advisory lock.

All demo contact addresses use reserved `example.org` addresses. During the task,
mail delivery is disabled and mail jobs use an isolated test adapter; the prior
mail settings are restored afterward. For interactive editing, keep the local
application's mail delivery configured for development too. The seed does not
install a login bypass, change existing staff permissions, or invoke scheduled
maintenance tasks.

The printed JSON summary reports created and existing jobs, the requested demo
job count, and counts by status, job type, and pickup location. These describe
the task's selected demo records rather than all records already in the database.
