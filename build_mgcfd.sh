#!/bin/bash

ARCH=TX2           # Build architecture, must be one of [TX2, A64FX]
COMPILER=clang     # Compiler, must be one of [clang, gnu, cray]
MGCFD_CC=cc        # C command
MGCFD_MPICC=cc     # MPICC command
MGCFD_CXX=CC       # C++ command
MGCFD_MPICXX=CC    # MPIC++ command
MGCFD_FC=ftn       # C++ command
MGCFD_MPIFC=ftn    # MPIC++ command
CRAY_SYSTEM=1      # Cray sytem? 0 or 1
MPI_DIR=
BUILD_HDF5=1


# If using cray system, load programming environments and HDF5
if [$CRAY_SYTEM -eq 1]
then
    PRGENV=`module -t list 2>&1 | grep PrgEnv`
    if [$COMPILER=clang]
    then
        module swap $PRGENV PrgEnv-allinea
        module load tools/arm-compiler/20.1
    fi
    if [$COMPILER=gnu]
    then
        module swap $PRGENV PrgEnv-gnu
    fi
    if [$COMPILER=cray]
    then
        module swap $PRGENV PrgEnv-cray
    fi
    BUILD_HDF5=0
    module load cray-hdf5-parallel
    MPI_DIR=$MPICH_DIR
fi

echo "Currently loaded modules:"
module li
echo ""
echo ""


###############
## Set up build
###############
printf "Script options: "
printf "ARCH:         $ARCH"
printf "COMPILER:     $COMPILER"
printf "MGCFD_CC:     $MGCFD_CC"
printf "MGCFD_MPICC:  $MGCFD_MPICC"
printf "MGCFD_CXX:    $MGCFD_CXX"
printf "MGCFD_MPICXX: $MGCFD_MPICXX"
printf "CRAY_SYSTEM:  $CRAY_SYSTEM"
printf "BUILD_HDF5:   $BUILD_HDF5"
echo ""


TOP_DIR=$PWD/MGCFD-$COMPILER-$ARCH
mkdir $TOP_DIR
cd $TOP_DIR

###############
## Build HDF5
###############
printf "Building HDF5...\n"
if [$BUILD_HDF5 -eq 0]
then
    mkdir HDF5
    cd HDF5
    mkdir build install
    HDF5_BUILD_DIR=$(realpath build)
    HDF5_INSTALL_DIR=$(realpath install)

    cd $BUILD_DIR
    wget https://s3.amazonaws.com/hdf-wordpress-1/wp-content/uploads/manual/HDF5/HDF5_1_10_5/source/hdf5-1.10.5.tar.gz
    tar -xf hdf5-1.10.5.tar

    cd hdf5-1.10.5
    ./configure CC=$MGCFD_CXX FC=$MGCFD_MPIFC CXX=$MGCFD_MPICXX --enable-parallel --enable-fortran --prefix=$HDF5_INSTALL_DIR --with-pic

    sed -i -e 's/wl=""/wl="-Wl,"/g' libtool
    sed -i -e 's/pic_flag=""/pic_flag=" -fPIC -DPIC"/g' libtool

    make
    make install
    HDF5_DIR=$HDF5_INSTALL_DIR
fi

###############
## Build PARMETIS
###############
cd $TOP_DIR
printf "Building PARMETIS...\n"
wget http://glaros.dtc.umn.edu/gkhome/fetch/sw/parmetis/parmetis-4.0.3.tar.gz
tar xvzf parmetis-4.0.3.tar.gz
cd parmetis-4.0.3

PARMETIS_INSTALL_DIR=$TOP_DIR/parmetis-4.0.3/install/

sed -i "s/cc         = not-set/cc         = $(MGCFD_MPICC)/" Makefile
sed -i "s/cxx        = not-set/cc         = $(MGCFD_MPICXX)/" Makefile
sed -i "s/prefix     = not-set/prefix     = $(PARMETIS_INSTALL_DIR)/" Makefile
make config
make -j
make install

sed -i "s/cc         = not-set/cc         = $(MGCFD_MPICC)/" Makefile
sed -i "s/prefix     = not-set/prefix     = $(PARMETIS_INSTALL_DIR)/" Makefile
make config
make -j
make install

## Build Scotch
cd $TOP_DIR
printf "Building Scotch...\n"
mkdir scotch
cd scotch

mkdir build install
SCOTCH_BUILD_DIR=$(realpath build)
SCOTCH_INSTALL_DIR=$(realpath install)

cd $BUILD_DIR
wget https://gforge.inria.fr/frs/download.php/file/38114/scotch_6.0.8.tar.gz
tar xf scotch_6.0.8.tar.gz
cd scotch_6.0.8/src

cp Make.inc/Makefile.inc.x86-64_pc_linux2 Makefile.inc
sed -i "s/mpicc/$(MGCFD_MPICC)/g" Makefile.inc
sed -i "s/gcc/$(MGCFD_CC)/g" Makefile.inc

prefix=$SCOTCH_INSTALL_DIR make scotch ptscotch
prefix=$SCOTCH_INSTALL_DIR make install

###############
## OP2-Common
###############
cd $TOP_DIR
printf "Building OP2-Common...\n"
git clone https://github.com/OP-DSL/OP2-Common.git
cd OP2-Common/op2/c/

OP2_COMPILER=$COMPILER
CPP_WRAPPER=$MGCFD_CXX
MPICPP_WRAPPER=$MGCFD_MPICXX
OP2_INSTALL_PATH=$TOP_DIR/OP2-Common/op2/
MPI_INSTALL_PATH=$MPI_DIR
PARMETIS_INSTALL_PATH=$PARMETIS_INSTALL_DIR
HDF5_INSTALL_PATH=$HDF5_DIR
PTSCOTCH_INSTALL_PATH=$SCOTCH_INSTALL_DIR
printf "LD PATHS:\n\tCC: $OP2_COMPILER\n\tOP2: $OP2_INSTALL_PATH\n\tMPI: $MPI_INSTALL_PATH\n\tPARMETIS: $PARMETIS_INSTALL_PATH\n\tHDF5: $HDF5_INSTALL_PATH\n\tPTSCOTCH: $PTSCOTCH_INSTALL_PATH\n"

export LD_LIBRARY_PATH=$MPI_INSTALL_PAT/lib:$PARMETIS_INSTALL_PATH/lib:$HDF5_INSTALL_PATH/lib:$PTSCOTCH_INSTALL_PATH/lib:$LD_LIBRARY_PATH

make clean core hdf5 seq mpi_seq

###############
## MG-CFD-OP2
###############
cd $TOP_DIR
printf "Building MG-CFD-OP2...\n"
git clone https://github.com/warwick-hpsc/MG-CFD-app-OP2
cd MG-CFD-app-OP2

make mpi_vec



