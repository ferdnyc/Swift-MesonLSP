#!/usr/bin/env bash
./scripts/create_license_bundle.sh
cd .debian || exit
chmod 0755 build/DEBIAN
mkdir -p build/usr/bin
mkdir -p build/usr/share/Swift-MesonLSP
cp ../COPYING build/usr/share/Swift-MesonLSP/
cp ../3rdparty.txt build/usr/share/Swift-MesonLSP/
cp ../out/Swift-MesonLSP build/usr/bin
dpkg-deb -Zgzip --build build
cp build.deb /Swift-MesonLSP-debian-stable.deb || exit 1
rm build.deb build/usr/bin/Swift-MesonLSP
cp ../out1/Swift-MesonLSP build/usr/bin
dpkg-deb -Zgzip --build build
cp build.deb /Swift-MesonLSP-debian-testing.deb || exit 1
rm build.deb build/usr/bin/Swift-MesonLSP
cp ../out2/Swift-MesonLSP build/usr/bin
dpkg-deb -Zgzip --build build
cp build.deb /Swift-MesonLSP-debian-unstable.deb || exit 1
rm build.deb build/usr/bin/Swift-MesonLSP
exit 0
