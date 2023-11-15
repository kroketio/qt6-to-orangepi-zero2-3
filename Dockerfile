FROM ubuntu:22.04

# PI_USER needs to be root
ARG PI_HOST=192.168.1.12
ARG PI_USER=root
ARG PI_PASSWORD=orangepi

ARG THREADS=8
ARG QT_VERSION=6.6.0
ARG MODULES=qtdeclarative,qtsvg,qtmultimedia,qtquick3d,qtlocation,qtsensors,qtconnectivity,qt3d,qtshadertools,qtimageformats,qtwebsockets,qtcharts,qtgraphs,qthttpserver,qtvirtualkeyboard,qtbase,qtpositioning
ENV SOURCE_DATE_EPOCH=1397818193

# host: requirements
RUN apt update && \
    DEBIAN_FRONTEND=noninteractive apt install -y curl rsync symlinks sshpass nano wget zip libgcrypt20-dev automake \
     build-essential cmake gettext git libtool pkg-config python3 libboost-all-dev libudev-dev libinput-dev libts-dev \
    libmtdev-dev libjpeg-dev libfontconfig1-dev libssl-dev libdbus-1-dev libglib2.0-dev libxkbcommon-dev \
    libegl1-mesa-dev libgbm-dev libgles2-mesa-dev mesa-common-dev libasound2-dev libpulse-dev gstreamer1.0-omx-generic \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev  gstreamer1.0-alsa libvpx-dev libsrtp2-dev libsnappy-dev \
    libnss3-dev "^libxcb.*" flex bison libxslt-dev ruby gperf libbz2-dev libcups2-dev libatkmm-1.6-dev libxi6 \
    libxcomposite1 libfreetype6-dev libicu-dev libsqlite3-dev libxslt1-dev libavcodec-dev libavformat-dev \
    libswscale-dev libx11-dev freetds-dev libsqlite3-dev libpq-dev libiodbc2-dev firebird-dev libgst-dev \
    libxext-dev libxcb1 libxcb1-dev libx11-xcb1 libx11-xcb-dev libxcb-keysyms1 libxcb-keysyms1-dev libxcb-image0 \
    libxcb-image0-dev libxcb-shm0 libxcb-shm0-dev libxcb-icccm4 libxcb-icccm4-dev libxcb-sync1 libxcb-sync-dev \
    libxcb-render-util0 libxcb-render-util0-dev libxcb-xfixes0-dev libxrender-dev libxcb-shape0-dev libxcb-randr0-dev \
    libxcb-glx0-dev libxi-dev libdrm-dev libxcb-xinerama0 libxcb-xinerama0-dev libatspi2.0-dev libxcursor-dev libxcomposite-dev \
    libxdamage-dev libxss-dev libxtst-dev libpci-dev libcap-dev libxrandr-dev libdirectfb-dev libaudio-dev \
    libxkbcommon-x11-dev gcc-aarch64-linux-gnu g++-aarch64-linux-gnu ninja-build make build-essential libclang-dev \
    gcc bison gperf pkg-config libfontconfig1-dev libfreetype6-dev libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev \
    libxi-dev libxrender-dev libxcb1-dev libxcb-glx0-dev libxcb-keysyms1-dev libxcb-image0-dev libxcb-shm0-dev \
    libxcb-icccm4-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-shape0-dev libxcb-randr0-dev libxcb-render-util0-dev \
    libxcb-util-dev libxcb-xinerama0-dev libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev libatspi2.0-dev \
    libgl1-mesa-dev libglu1-mesa-dev freeglut3-dev zlib1g-dev libpng-dev libpng-dev libqrencode-dev libevent-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /z2w/

# host: prepare directory structures
RUN mkdir -p sysroot/usr && \
    mkdir -p sysroot/opt && \
    mkdir -p target && \
    mkdir -p targetbuild && \
    mkdir -p host && \
    mkdir -p hostbuild

# host: clone Qt6
RUN git clone -b $QT_VERSION --depth 1 https://codereview.qt-project.org/qt/qt5 qt6 && cd qt6 && \
    git reset --hard 244fc454356bc9fb31a30692b8645cbfd91dc52c

# host: init Qt6 modules
WORKDIR /z2w/qt6
RUN ./init-repository --module-subset=$MODULES -f

# host: copy zero2w mkspec
WORKDIR /z2w/
COPY toolchain.cmake .
COPY mkspec-linux-orangepi-zero2w-aarch64 qt6/qtbase/mkspecs/devices/linux-orangepi-zero2w-aarch64

# host: compile Qt6 (12min)
WORKDIR /z2w/hostbuild
RUN cmake ../qt6 -GNinja -DCMAKE_BUILD_TYPE=Release -DFEATURE_dbus=OFF -DQT_BUILD_EXAMPLES=OFF \
    -DQT_BUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX=$PWD/../host && \
    cmake --build . --parallel $THREADS && \
    cmake --install . && \
    rm -rf *

WORKDIR /z2w
# device: prepare final Qt6 dir
RUN sshpass -p "$PI_PASSWORD" ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$PI_USER@$PI_HOST" \
    'mkdir -p /usr/local/qt6'

# device: replace apt mirror
RUN sshpass -p "$PI_PASSWORD" ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$PI_USER@$PI_HOST" \
    'sed -i -e "s/repo.huaweicloud.com/ports.ubuntu.com/g" /etc/apt/sources.list'

# device: copy over apt-get commands
COPY pi_requirements.sh .
RUN sshpass -p "$PI_PASSWORD" scp -o PreferredAuthentications=password -o StrictHostKeyChecking=no pi_requirements.sh "$PI_USER@$PI_HOST:/tmp/requirements.sh"

# device: requirements (6min)
RUN sshpass -p "$PI_PASSWORD" ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$PI_USER@$PI_HOST" \
    'bash /tmp/requirements.sh'

# device: creating sysroot.tar (2min)
RUN sshpass -p "$PI_PASSWORD" ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$PI_USER@$PI_HOST" \
    'cd / && tar cvf /sysroot.tar /usr/include/ /lib /usr/lib'
# device: fetching sysroot (1gb file, time estimate depends on your network speed)
RUN sshpass -p "$PI_PASSWORD" scp -r -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$PI_USER@$PI_HOST:/sysroot.tar" sysroot/
# device: cleanup sysroot.tar
RUN sshpass -p "$PI_PASSWORD" ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$PI_USER@$PI_HOST" \
    'rm /sysroot.tar'

# host: unpack sysroot.tar
WORKDIR /z2w/sysroot/
RUN tar -xvf sysroot.tar
# host: fix symlinks
WORKDIR /z2w/
RUN symlinks -rc sysroot

# host: cross-compile Qt (12min)
WORKDIR /z2w/targetbuild
RUN cmake ../qt6 -GNinja -DCMAKE_BUILD_TYPE=Release -DINPUT_opengl=es2 -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF \
    -DQT_HOST_PATH=$PWD/../host -DCMAKE_INSTALL_PREFIX=/usr/local/qt6 -DCMAKE_STAGING_PREFIX=$PWD/../target \
    -DCMAKE_TOOLCHAIN_FILE=$PWD/../toolchain.cmake -DQT_QMAKE_TARGET_MKSPEC=devices/linux-orangepi-zero2w-aarch64 \
    -DQT_FEATURE_xcb=ON -DFEATURE_xcb_xlib=ON -DQT_FEATURE_xlib=ON -DFEATURE_dbus=OFF && \
    cmake --build . --parallel $THREADS && \
    cmake --install . && \
    rm -rf *

WORKDIR /z2w/target
RUN tar cvf target.tar *

# device: uploading Qt6 build (280mb file, time estimate depends on your network speed)
RUN sshpass -p "$PI_PASSWORD" scp -r -o PreferredAuthentications=password -o StrictHostKeyChecking=no target.tar "$PI_USER@$PI_HOST:/usr/local/qt6/"
RUN rm target.tar
# device: extracting Qt6 build
RUN sshpass -p "$PI_PASSWORD" ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no "$PI_USER@$PI_HOST" \
    'cd /usr/local/qt6/ && tar -xvf target.tar && rm target.tar'

# device: setting ENV
RUN echo 'export PATH="$PATH:/z2w/target/bin/"' >> /root/.bashrc
ENV PATH=${PATH}:/z2w/target/bin/

RUN git config --global --add safe.directory /app
