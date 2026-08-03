kind: import

description: |
  Minimal pinned Autotools overlay for Ubuntu Base 24.04.

  The base already contains glibc, coreutils, dpkg and perl-base. These Ubuntu
  packages add only Autoconf, Automake, Libtool, GNU Make, M4, pkgconf and
  libtool's file(1) probe. Every .deb is pinned by versioned pool URL and
  SHA-256; package maintainer scripts are neither needed nor executed.

sources:
- kind: deb
  url: ubuntu-archive:pool/main/m/m4/m4_1.4.19-4build1_amd64.deb
  ref: 30ea715845a1863abd55d11e47ab91513130bf347852d4cdeae69e9d98fa795c
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/a/autoconf/autoconf_2.71-3_all.deb
  ref: cc3f9f7a1e576173fb59c36652c0a67c6426feae752b352404ba92dfcb1b26c9
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/a/autotools-dev/autotools-dev_20220109.1_all.deb
  ref: d909f0327b09d9a9136239caca975df89782fa28efd721c4eb4caea422d3fc5a
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/a/automake-1.16/automake_1.16.5-1.3ubuntu1_all.deb
  ref: 5ae9a98e73545002cd891f028859941af2a3c760cb6190e635c7ef36953912de
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/libt/libtool/libtool_2.4.7-7build1_all.deb
  ref: 9d1d707179675d38e024bb13613b1d99e0d33fa6c45e5f3bcba19340781781d3
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/libt/libtool/libltdl7_2.4.7-7build1_amd64.deb
  ref: 02d0d2d7e1bf73f838a92f8df7a9b07b698c837e82bd89aee6a581cf793cd966
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/libt/libtool/libltdl-dev_2.4.7-7build1_amd64.deb
  ref: 3a706efe1d9d8b493bd2335fabaa9ec28549c9134750fad6c0a5aa9868c6ee9c
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/m/make-dfsg/make_4.3-4.1build2_amd64.deb
  ref: 1fe6a815b56c7b6e9ce4086a363f09444bbd0a0d30e230c453d0b78e44b57a99
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/p/pkgconf/libpkgconf3_1.8.1-2build1_amd64.deb
  ref: fc3a57e8f931ec06cb7c51acc56878f1fec247ff02a7adcab26905c2faeb2792
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/p/pkgconf/pkgconf-bin_1.8.1-2build1_amd64.deb
  ref: 7a812f05ee1610154b433e2ad54f6e4163fcbb306b9fb31afe959afb2e5e1545
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/p/pkgconf/pkgconf_1.8.1-2build1_amd64.deb
  ref: 834a58031069d97d7cfb8b2f5bfd5effc69cecf7f30cc362071875f1f8dc1828
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/f/file/libmagic-mgc_5.45-3build1_amd64.deb
  ref: f0ed0e314a63ae1b7e5403d7e43a26c6e0c0ee69e9a305babcf9c6775607377a
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/f/file/libmagic1t64_5.45-3build1_amd64.deb
  ref: fc2319f342c437e044ccf854e0c95bd472a7eb0b9363e1f76ad1524ab04df68e
  base-dir: ""
- kind: deb
  url: ubuntu-archive:pool/main/f/file/file_5.45-3build1_amd64.deb
  ref: 17dae1d6e803d0304e318f451c8abf62cbd5bb2a0068300cdeea77c62075b895
  base-dir: ""
