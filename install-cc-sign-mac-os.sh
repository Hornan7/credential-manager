ARCH="$(arch)"
if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "i386" ]];
then
  ZIP_URL="https://github.com/IntersectMBO/credential-manager/releases/download/0.1.1.0/cc-sign-mac-os-intel.zip"
else
  ZIP_URL="https://github.com/IntersectMBO/credential-manager/releases/download/0.1.1.0/cc-sign-mac-os-arm.zip"
fi

curl -L --output /tmp/cc-sign.zip $ZIP_URL
unzip /tmp/cc-sign.zip -d /tmp
cp -n /tmp/result/bin/*.dylib /usr/local/lib
cp /tmp/result/bin/cc-sign /usr/local/bin
rm -rf /tmp/result
