#!/usr/bin/env bash
#
# build_nemo_library.sh NEMO_SOURCE OUTPUT_DIR CONFIG_NAME [--mpi]
#
# Builds NEMO 4.2.x as a shared library callable from Julia.
#
#   NEMO_SOURCE    path to a NEMO 4.2.x source tree (must contain makenemo, cfgs/, arch/, src/)
#   OUTPUT_DIR     destination for libnemo.{dylib,so} and run/
#   CONFIG_NAME    name for the new configuration (created under NEMO_SOURCE/cfgs/)
#   --mpi          enable MPI (resolves MPI_HOME from mpifort on PATH if unset)

set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"

use_mpi=0
positional=()
for argument in "$@"; do
    case "$argument" in
        --mpi) use_mpi=1 ;;
        *)     positional+=("$argument") ;;
    esac
done

if [ ${#positional[@]} -lt 3 ]; then
    echo "Usage: $0 NEMO_SOURCE OUTPUT_DIR CONFIG_NAME [--mpi]" >&2
    exit 1
fi

nemo_source="${positional[0]}"
output_directory="${positional[1]}"
configuration_name="${positional[2]}"

reference_configuration="ORCA2_ICE_PISCES"
build_directory="$output_directory/build"
run_directory="$output_directory/run"
build_log="$output_directory/build.log"
wrapper_source="$script_directory/nemo_wrapper.F90"
error_handler_source="$script_directory/nemo_error_handler.c"

[ -d "$nemo_source" ]             || { echo "NEMO source not found: $nemo_source" >&2; exit 1; }
[ -f "$wrapper_source" ]          || { echo "Wrapper source not found: $wrapper_source" >&2; exit 1; }
[ -f "$error_handler_source" ]    || { echo "Error handler source not found: $error_handler_source" >&2; exit 1; }
command -v gfortran > /dev/null   || { echo "gfortran not found on PATH" >&2; exit 1; }

mkdir -p "$output_directory" "$build_directory" "$run_directory"

operating_system="$(uname -s)"

case "$operating_system" in
    Darwin) architecture_label="darwin"; shared_library_name="libnemo.dylib";;
    Linux)  architecture_label="linux";  shared_library_name="libnemo.so";;
    *) echo "Unsupported operating system: $operating_system" >&2; exit 1;;
esac

cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

architecture_file="$nemo_source/arch/arch-julia-${architecture_label}.fcm"

mpi_compile_flags=""
mpi_link_flags=""
mpi_include_flags=""

if [ "$use_mpi" -eq 1 ]; then
    if [ -z "${MPI_HOME:-}" ]; then
        mpifort_executable="$(command -v mpifort 2>/dev/null || command -v mpif90 2>/dev/null || true)"
        if [ -n "$mpifort_executable" ]; then
            mpifort_real="$(readlink -f "$mpifort_executable" 2>/dev/null || python3 -c "import os; print(os.path.realpath('$mpifort_executable'))")"
            MPI_HOME="$(dirname "$(dirname "$mpifort_real")")"
            export MPI_HOME
        fi
    fi
    [ -n "${MPI_HOME:-}" ] || { echo "MPI requested but MPI_HOME could not be resolved" >&2; exit 1; }
    mpi_include_flags="-I${MPI_HOME}/include"
    mpi_fortran_library="-lmpifort"
    [ -f "${MPI_HOME}/lib/libmpi_mpifh.dylib" ] || [ -f "${MPI_HOME}/lib/libmpi_mpifh.so" ] && mpi_fortran_library="-lmpi_mpifh"
    mpi_link_flags="-L${MPI_HOME}/lib -Wl,-rpath,${MPI_HOME}/lib -lmpi $mpi_fortran_library"
fi

netcdf_fortran_prefix="$(nf-config --prefix 2>/dev/null || true)"
netcdf_c_prefix="$(nc-config --prefix 2>/dev/null || true)"
[ -n "$netcdf_fortran_prefix" ] || { echo "nf-config not found; install netcdf-fortran" >&2; exit 1; }
[ -n "$netcdf_c_prefix" ]       || { echo "nc-config not found; install netcdf-c" >&2; exit 1; }

cat > "$architecture_file" <<ARCHITECTURE_END
%NCDF_HOME     ${netcdf_fortran_prefix}
%NCDFC_HOME    ${netcdf_c_prefix}
%NCDF_INC      -I%NCDF_HOME/include
%NCDF_LIB      -L%NCDF_HOME/lib -Wl,-rpath,%NCDF_HOME/lib -lnetcdff -L%NCDFC_HOME/lib -Wl,-rpath,%NCDFC_HOME/lib -lnetcdf

%CPP           cpp -Dkey_nosignedzero
%FC            gfortran
%FCFLAGS       -fdefault-real-8 -O2 -funroll-all-loops -fcray-pointer -ffree-line-length-none -fallow-argument-mismatch -fPIC $mpi_include_flags
%FFLAGS        %FCFLAGS
%LD            gfortran
%FPPFLAGS      -P -traditional
%LDFLAGS       -fPIC $mpi_link_flags
%AR            ar
%ARFLAGS       rs
%MK            make
%USER_INC      %NCDF_INC $mpi_include_flags
%USER_LIB      %NCDF_LIB

%CC            cc
%CFLAGS        -O0 -fPIC
ARCHITECTURE_END

configuration_path="$nemo_source/cfgs/$configuration_name"
user_source_directory="$configuration_path/MY_SRC"

if [ -d "$configuration_path" ]; then
    echo "Reusing existing configuration $configuration_name (delete '$configuration_path' for a fresh build)"
else
    echo "Creating configuration $configuration_name from $reference_configuration..."
    (cd "$nemo_source" && \
        ./makenemo -m "julia-${architecture_label}" \
                   -r "$reference_configuration" \
                   -n "$configuration_name" \
                   -j 0) >> "$build_log" 2>&1 || { tail -40 "$build_log" >&2; exit 1; }
fi

mkdir -p "$user_source_directory"
cp "$wrapper_source" "$user_source_directory/nemo_wrapper.F90"

cpp_file="$configuration_path/cpp_${configuration_name}.fcm"
[ -f "$cpp_file" ] || { echo "cpp file not found: $cpp_file" >&2; exit 1; }

python3 - "$cpp_file" "$use_mpi" <<'PYTHON_END'
import sys
path, use_mpi = sys.argv[1], int(sys.argv[2])
with open(path) as handle:
    raw = handle.read()
prefix, _, tokens = raw.partition("bld::tool::fppkeys")
keys = [token for token in tokens.split() if token not in ("key_top", "key_xios", "key_pisces")]
if use_mpi == 0 and "key_mpi_off" not in keys:
    keys.append("key_mpi_off")
elif use_mpi == 1 and "key_mpi_off" in keys:
    keys.remove("key_mpi_off")
with open(path, "w") as handle:
    handle.write(prefix + "bld::tool::fppkeys   " + " ".join(keys) + "\n")
PYTHON_END

echo "Adjusted CPP keys; final cpp file:"
cat "$cpp_file"

echo "Compiling NEMO ($cpu_count parallel jobs); log: $build_log"
(cd "$nemo_source" && \
    ./makenemo -m "julia-${architecture_label}" \
               -r "$reference_configuration" \
               -n "$configuration_name" \
               -j "$cpu_count") >> "$build_log" 2>&1 || { tail -60 "$build_log" >&2; exit 1; }

build_artifacts="$configuration_path/BLD/obj"
[ -d "$build_artifacts" ] || { echo "Build did not produce $build_artifacts" >&2; tail -40 "$build_log" >&2; exit 1; }

object_files=$(find "$build_artifacts" -name '*.o' ! -name 'nemo.o' | tr '\n' ' ')
[ -n "$object_files" ] || { echo "No object files found in $build_artifacts" >&2; exit 1; }

error_handler_object="$build_directory/nemo_error_handler.o"
cc -O2 -fPIC -c "$error_handler_source" -o "$error_handler_object"

if [ "$operating_system" = "Darwin" ]; then
    link_flags="-dynamiclib -install_name @rpath/${shared_library_name}"
else
    link_flags="-shared"
fi

echo "Linking $shared_library_name..."
gfortran $link_flags \
    -o "$output_directory/${shared_library_name}" \
    $object_files \
    "$error_handler_object" \
    -L"${netcdf_fortran_prefix}/lib" -Wl,-rpath,"${netcdf_fortran_prefix}/lib" -lnetcdff \
    -L"${netcdf_c_prefix}/lib"       -Wl,-rpath,"${netcdf_c_prefix}/lib"       -lnetcdf \
    $mpi_link_flags

experiment_directory=""
for candidate in "$nemo_source/cfgs/$reference_configuration/EXPREF" "$configuration_path/EXP00" "$configuration_path/EXPREF"; do
    [ -d "$candidate" ] && { experiment_directory="$candidate"; break; }
done
[ -n "$experiment_directory" ] || { echo "No experiment directory found near $configuration_path" >&2; exit 1; }

echo "Copying experiment files from $experiment_directory to $run_directory"
cp -r "$experiment_directory"/. "$run_directory/"
ln -sf "$output_directory/${shared_library_name}" "$run_directory/${shared_library_name}"

for required in namelist_cfg namelist_ref; do
    [ -f "$run_directory/$required" ] || { echo "ERROR: $required missing from $run_directory after copy" >&2; ls -la "$run_directory" >&2; exit 1; }
done

echo "Run directory contents:"
ls -la "$run_directory"

echo "Built  $output_directory/${shared_library_name}"
echo "Run    $run_directory"
