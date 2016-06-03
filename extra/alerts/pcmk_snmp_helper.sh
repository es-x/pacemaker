#!/bin/sh
#
# Description:  Manages a SNMP trap, provided by NTT OSSC as an
#               script under Heartbeat/LinuxHA control
#
# Copyright (c) 2016 NIPPON TELEGRAPH AND TELEPHONE CORPORATION
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
#
##############################################################################
# This sample script assumes that only users who already have root access can
# edit the CIB. Otherwise, a malicious user could run commands as hacluster by
# inserting shell code into the trap_options variable. If that is not the case
# in your environment, you should edit this script to remove or validate
# trap_options.
#
# Sample configuration (cib fragment in xml notation)
# ================================
# <configuration>
#   <alerts>
#     <alert id="snmp_alert" path="/path/to/pcmk_snmp_helper.sh">
#       <instance_attributes id="config_for_snmp_helper">
#         <nvpair id="trap_node_states" name="trap_node_states" value="all"/>
#       </instance_attributes>
#       <meta_attributes id="config_for_timestamp">
#         <nvpair id="ts_fmt" name="timestamp-format" value=""%Y-%m-%d,%H:%M:%S.%01N""/>
#       </meta_attributes>
#       <recipient id="snmp_destination" value="192.168.1.2"/>
#     </alert>
#   </alerts>
# </configuration>
# ================================
# ================================
# <configuration>
#   <alerts>
#     <alert id="snmp_alert" path="/path/to/pcmk_snmp_helper.sh">
#       <recipient id="snmp_destination" value="192.168.1.2">
#         <instance_attributes id="config_for_snmp_helper">
#           <nvpair id="trap_node_states" name="trap_node_states" value="all"/>
#         </instance_attributes>
#         <meta_attributes id="config_for_timestamp">
#           <nvpair id="ts_fmt" name="timestamp-format" value=""%Y-%m-%d,%H:%M:%S.%01N""/>
#         </meta_attributes>
#       </recipient>
#     </alert>
#   </alerts>
# </configuration>
# ================================

if [ -z "$CRM_alert_version" ]; then
    echo "Pacemaker version 1.1.15 or later is required"
    exit 0
fi

#
trap_binary_default="/usr/bin/snmptrap"
trap_version_default="2c"
trap_options_default=""
trap_community_default="public"
trap_node_states_default="all"
trap_fencing_tasks_default="all"
trap_resource_tasks_default="all"
trap_monitor_success_default="false"
trap_add_hires_timestamp_oid_default="true"

: ${trap_binary=${trap_binary_default}}
: ${trap_version=${trap_version_default}}
: ${trap_options=${trap_options_default}}
: ${trap_community=${trap_community_default}}
: ${trap_node_states=${trap_node_states_default}}
: ${trap_fencing_tasks=${trap_fencing_tasks_default}}
: ${trap_resource_tasks=${trap_resource_tasks_default}}
: ${trap_monitor_success=${trap_monitor_success_default}}
: ${trap_add_hires_timestamp_oid=${trap_add_hires_timestamp_oid_default}}

if [ "${trap_add_hires_timestamp_oid}" = "true" ]
    hires_timestamp="HOST-RESOURCES-MIB::hrSystemDate s \"${CRM_alert_timestamp}\""
fi

is_in_list() {
    item_list=`echo "$1" | tr ',' ' '`

    if [ "${item_list}" = "all" ]; then
        return 0
    else
        for act in $item_list
        do
            act=`echo "$act" | tr A-Z a-z`
            [ "$act" != "$2" ] && continue
            return 0
        done
    fi
    return 1
}

case "$CRM_alert_kind" in
    node)
        is_in_list "${trap_node_states}" "${CRM_alert_desc}"
        [ $? -ne 0 ] && exit 0

        "${trap_binary}" -v "${trap_version}" ${trap_options} \
        -c "${trap_community}" "${CRM_alert_recipient}" "" \
        PACEMAKER-MIB::pacemakerNotificationTrap \
        PACEMAKER-MIB::pacemakerNotificationNode s "${CRM_alert_node}" \
        PACEMAKER-MIB::pacemakerNotificationDescription s "${CRM_alert_desc}" \
        ${hires_timestamp}
        ;;
    fencing)
        is_in_list "${trap_fencing_tasks}" "${CRM_alert_task}"
        [ $? -ne 0 ] && exit 0

        "${trap_binary}" -v "${trap_version}" ${trap_options} \
        -c "${trap_community}" "${CRM_alert_recipient}" "" \
        PACEMAKER-MIB::pacemakerNotificationTrap \
        PACEMAKER-MIB::pacemakerNotificationNode s "${CRM_alert_node}" \
        PACEMAKER-MIB::pacemakerNotificationOperation s "${CRM_alert_task}" \
        PACEMAKER-MIB::pacemakerNotificationDescription s "${CRM_alert_desc}" \
        PACEMAKER-MIB::pacemakerNotificationReturnCode i ${CRM_alert_rc} \
        ${hires_timestamp}
        ;;
    resource)
        is_in_list "${trap_resource_tasks}" "${CRM_alert_task}"
        [ $? -ne 0 ] && exit 0

        case "${CRM_alert_desc}" in
        Cancelled) ;;
        *)
            if [ "${trap_monitor_success}" = "false" ]; then
                if [[ ${CRM_alert_rc} -eq 0 && "${CRM_alert_task}" == "monitor" ]]; then
                    exit;
                fi
            fi

            "${trap_binary}" -v "${trap_version}" ${trap_options} \
            -c "${trap_community}" "${CRM_alert_recipient}" "" \
            PACEMAKER-MIB::pacemakerNotificationTrap \
            PACEMAKER-MIB::pacemakerNotificationNode s "${CRM_alert_node}" \
            PACEMAKER-MIB::pacemakerNotificationResource s "${CRM_alert_rsc}" \
            PACEMAKER-MIB::pacemakerNotificationOperation s "${CRM_alert_task}" \
            PACEMAKER-MIB::pacemakerNotificationDescription s "${CRM_alert_desc}" \
            PACEMAKER-MIB::pacemakerNotificationStatus i ${CRM_alert_status} \
            PACEMAKER-MIB::pacemakerNotificationReturnCode i ${CRM_alert_rc} \
            PACEMAKER-MIB::pacemakerNotificationTargetReturnCode i ${CRM_alert_target_rc} \
            ${hires_timestamp}
            ;;
        esac
        ;;
    *)
        ;;
esac
