FROM ubuntu:bionic-20220427 as builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
                    apt-transport-https \
                    bc \
                    build-essential \
                    ca-certificates \
                    gnupg \
                    ninja-build \
                    git \
                    software-properties-common \
                    wget \
                    zlib1g-dev

RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null \
    | apt-key add - \
  && apt-add-repository -y 'deb https://apt.kitware.com/ubuntu/ bionic main' \
  && apt-get update \
  && apt-get -y install cmake=3.18.3-0kitware1 cmake-data=3.18.3-0kitware1


RUN git clone https://github.com/ANTsX/ANTs.git \
    && mkdir -p /tmp/ants/build \
    && mv ANTs /tmp/ants/source \
    && cd /tmp/ants/build \
    && mkdir -p /opt/ants \
    && git config --global url."https://".insteadOf git:// \
    && cmake \
      -GNinja \
      -DBUILD_TESTING=ON \
      -DRUN_LONG_TESTS=OFF \
      -DRUN_SHORT_TESTS=ON \
      -DBUILD_SHARED_LIBS=ON \
      -DCMAKE_INSTALL_PREFIX=/opt/ants \
      /tmp/ants/source \
    && cmake --build . --parallel \
    && cd ANTS-build \
    && cmake --install .

ENV ANTSPATH="/opt/ants/bin" \
    PATH="/opt/ants/bin:$PATH" \
    LD_LIBRARY_PATH="/opt/ants/lib:$LD_LIBRARY_PATH"

FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    python \
    tar \
    bzip2 \
    libssl-dev \
    dc \
    perl \
    tcsh \
    unzip \
    bc \
    zlib1g-dev \
    wget &&\
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
    
#fsl
RUN wget https://fsl.fmrib.ox.ac.uk/fsldownloads/fslinstaller.py && \
    python fslinstaller.py -d /opt/fsl -V 6.0.4

# Install Convert3D (stable build 1.0.0)
RUN wget -O c3d-1.0.0-Linux-x86_64.tar.gz "https://downloads.sourceforge.net/project/c3d/c3d/1.0.0/c3d-1.0.0-Linux-x86_64.tar.gz?r=https%3A%2F%2Fsourceforge.net%2Fprojects%2Fc3d%2Ffiles%2Fc3d%2F1.0.0%2Fc3d-1.0.0-Linux-x86_64.tar.gz%2Fdownload&ts=1571934949" && \
    tar -xf c3d-1.0.0-Linux-x86_64.tar.gz -C /opt/ && \
    rm c3d-1.0.0-Linux-x86_64.tar.gz

# freesurfer
RUN wget https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/6.0.0/freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz && \
    tar -C /opt -xzvf freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz && \
    echo "This is a dummy license file. Please bind your freesurfer license file to this file." > /opt/freesurfer/license.txt &&\
    rm freesurfer-Linux-centos6_x86_64-stable-pub-v6.0.0.tar.gz && \
    cd /

# miniconda
ENV PATH="/opt/miniconda3/bin:${PATH}"

RUN wget https://repo.anaconda.com/miniconda/Miniconda3-py39_4.12.0-Linux-x86_64.sh && \
    mkdir /opt/.conda && \
    bash Miniconda3-py39_4.12.0-Linux-x86_64.sh -b -p /opt/miniconda3 && \
    rm -f Miniconda3-py39_4.12.0-Linux-x86_64.sh

RUN conda install -c mrtrix3 mrtrix3 && \
    conda install pytorch torchvision torchaudio cudatoolkit=11.3 -c pytorch && \
    conda install -c conda-forge nibabel && \
    conda install numpy && \
    conda clean -a -y

# ANTs
COPY --from=builder /opt/ants /opt/ants

ENV FSLDIR=/opt/fsl
ENV PATH=${FSLDIR}/bin:${PATH}

ENV ANTSPATH="/opt/ants/bin" \
    PATH="/opt/ants/bin:$PATH" \
    LD_LIBRARY_PATH="/opt/ants/lib:$LD_LIBRARY_PATH"

ENV PATH="/opt/c3d-1.0.0-Linux-x86_64/bin:$PATH"

ENV FREESURFER_HOME=/opt/freesurfer

RUN mkdir /home/INPUTS && \
    mkdir /home/OUTPUTS

COPY src /home

SHELL ["/bin/bash", "-c"]
ENTRYPOINT ["/home/pipeline.sh"]