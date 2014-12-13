cheek
=====

cheek is a utility for bootstrapping a Cumulus Linux vm image.

### Disclaimer
This project is very much a work in progress, and is unsupported by Cumulus Networks®.  At this stage rather than executing it, it is best use as a commented copy-paste protocol. Some stages of package install end with errors which can be ignored. Caveat emptor: this process involves creating and formatting storage. Users should know what a loopback device is.

### Todos
Decreasing priority:
- Document software prerequisites
- Parameterize release version
- stderr/stdout handling
- Idempotency.  Trap and gracefully handle errors.
- --help
- Port to ppc
- Option for output image format
