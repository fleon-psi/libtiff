#!/bin/bash -eu
# Copyright (c) 1988-1997 Sam Leffler
# Copyright (c) 1991-1997 Silicon Graphics, Inc.
#
# Permission to use, copy, modify, distribute, and sell this software and
# its documentation for any purpose is hereby granted without fee, provided
# that (i) the above copyright notices and this permission notice appear in
# all copies of the software and related documentation, and (ii) the names of
# Sam Leffler and Silicon Graphics may not be used in any advertising or
# publicity relating to the software without the specific, prior written
# permission of Sam Leffler and Silicon Graphics.
#
# THE SOFTWARE IS PROVIDED "AS-IS" AND WITHOUT WARRANTY OF ANY KIND,
# EXPRESS, IMPLIED OR OTHERWISE, INCLUDING WITHOUT LIMITATION, ANY
# WARRANTY OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
#
# IN NO EVENT SHALL SAM LEFFLER OR SILICON GRAPHICS BE LIABLE FOR
# ANY SPECIAL, INCIDENTAL, INDIRECT OR CONSEQUENTIAL DAMAGES OF ANY KIND,
# OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
# WHETHER OR NOT ADVISED OF THE POSSIBILITY OF DAMAGE, AND ON ANY THEORY OF
# LIABILITY, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
# OF THIS SOFTWARE.

# build zlib
pushd "$SRC/zlib"
./configure --static --prefix="$WORK"
make -j$(nproc) CFLAGS="$CFLAGS -fPIC"
make install
popd

# Build libjpeg-turbo
pushd "$SRC/libjpeg-turbo"
cmake . -DCMAKE_INSTALL_PREFIX=$WORK -DENABLE_STATIC=on -DENABLE_SHARED=off
make -j$(nproc)
make install
popd

# Build libjbig
pushd "$SRC/jbigkit"
if [ "$ARCHITECTURE" = "i386" ]; then
    echo "#!/bin/bash" > gcc
    echo "clang -m32 \$*" >> gcc
    chmod +x gcc
    PATH=$PWD:$PATH make lib
else
    make lib
fi

mv "$SRC"/jbigkit/libjbig/*.a "$WORK/lib/"
mv "$SRC"/jbigkit/libjbig/*.h "$WORK/include/"
popd

if [ "$ARCHITECTURE" != "i386" ]; then
    apt-get install -y liblzma-dev
fi

cmake . -DCMAKE_INSTALL_PREFIX=$WORK -DBUILD_SHARED_LIBS=off
make -j$(nproc)
make install

$CXX $CXXFLAGS \
    -I $SRC/libtiff/contrib/stream -I $WORK/include \
    $SRC/libtiff/contrib/stream/tiffstream.cpp \
    -c -o tiffstream.o
ar -q $WORK/lib/libtiff.a tiffstream.o

EXTRA_ARGS=""
if [ "$ARCHITECTURE" != "i386" ]; then
    EXTRA_ARGS="-Wl,-Bstatic -llzma -Wl,-Bdynamic"
fi

mkdir afl_testcases
(cd afl_testcases; tar xf "$SRC/afl_testcases.tgz")
mkdir tif
find afl_testcases -type f -name '*.tif' -exec mv -n {} tif/ \;
zip -rj tif.zip tif/

for fuzzer in $SRC/libtiff/contrib/oss-fuzz/*_fuzzer.cc; do
  fuzzer_basename=$(basename -s .cc $fuzzer)
  $CXX $CXXFLAGS -std=c++11 \
      -I $WORK/include -I $SRC/libtiff \
      $fuzzer -o $OUT/$fuzzer_basename $LIB_FUZZING_ENGINE \
      $WORK/lib/libtiffxx.a $WORK/lib/libtiff.a $WORK/lib/libz.a \
      $WORK/lib/libjpeg.a $WORK/lib/libjbig.a $WORK/lib/libjbig85.a $EXTRA_ARGS
  cp tif.zip "$OUT/${fuzzer_basename}_seed_corpus.zip"
  cp $SRC/tiff.dict "$OUT/${fuzzer_basename}.dict"

done
