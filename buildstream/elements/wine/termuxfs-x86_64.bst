kind: import

description: |
  Pinned x86_64 Termux build sysroot used by the Proton Wine Unix side.

sources:
- kind: tar
  url: winnative-assets:Assets/termuxfs-x86_64.tar
  ref: 24f9223c2d268e0c8660de2ff9b6c11ef10f60e03a3f20a6a14a96dd703222ee
  base-dir: termuxfs/x86_64/data/data/com.termux/files/usr
