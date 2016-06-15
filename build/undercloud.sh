#!/bin/sh
##############################################################################
# Copyright (c) 2015 Tim Rozet (Red Hat), Dan Radez (Red Hat) and others.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################
set -e
source ./cache.sh
source ./variables.sh
source ./functions.sh

populate_cache "$rdo_images_uri/undercloud.qcow2"
if [ ! -d images ]; then mkdir images/; fi
cp -f cache/undercloud.qcow2 images/undercloud_build.qcow2

# prep opnfv-tht for undercloud
clone_fork opnfv-tht
pushd opnfv-tht > /dev/null
git archive --format=tar.gz --prefix=openstack-tripleo-heat-templates/ HEAD > ../opnfv-tht.tar.gz
popd > /dev/null

pushd images > /dev/null
# installing forked opnfv-tht
# enabling ceph OSDs to live on the controller
# OpenWSMan package update supports the AMT Ironic driver for the TealBox
# seeding configuration files specific to OPNFV
LIBGUESTFS_BACKEND=direct virt-customize \
    --upload ../opnfv-tht.tar.gz:/usr/share \
    --run-command "cd /usr/share && rm -rf openstack-tripleo-heat-templates && tar xzf opnfv-tht.tar.gz" \
    --run-command "sed -i '/ControllerEnableCephStorage/c\\  ControllerEnableCephStorage: true' /usr/share/openstack-tripleo-heat-templates/environments/storage-environment.yaml" \
    --run-command "sed -i '/ComputeEnableCephStorage/c\\  ComputeEnableCephStorage: true' /usr/share/openstack-tripleo-heat-templates/environments/storage-environment.yaml" \
    --run-command "curl http://download.opensuse.org/repositories/Openwsman/CentOS_CentOS-7/Openwsman.repo > /etc/yum.repos.d/wsman.repo" \
    --run-command "yum update -y openwsman*" \
    --run-command "cp /usr/share/instack-undercloud/undercloud.conf.sample /home/stack/undercloud.conf && chown stack:stack /home/stack/undercloud.conf" \
    --upload ../opnfv-environment.yaml:/home/stack/ \
    --upload ../virtual-environment.yaml:/home/stack/ \
    -a undercloud_build.qcow2

# Add custom IPA to allow kernel params
wget https://raw.githubusercontent.com/trozet/ironic-python-agent/opnfv_kernel/ironic_python_agent/extensions/image.py
python3.4 -c 'import py_compile; py_compile.compile("image.py", cfile="image.pyc")'

# Add performance image scripts
LIBGUESTFS_BACKEND=direct virt-customize --upload ../build_perf_image.sh:/home/stack \
                                         --upload ../set_perf_images.sh:/home/stack \
                                         --upload image.py:/root \
                                         --upload image.pyc:/root \
                                         -a undercloud_build.qcow2

mv -f undercloud_build.qcow2 undercloud.qcow2
popd > /dev/null