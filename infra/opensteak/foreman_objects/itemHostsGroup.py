#!/usr/bin/python3
# -*- coding: utf-8 -*-
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
#    Authors:
#     David Blaisonneau <david.blaisonneau@orange.com>
#     Arnaud Morin <arnaud1.morin@orange.com>

from opensteak.foreman_objects.item import ForemanItem


class ItemHostsGroup(ForemanItem):
    """
    ItemHostsGroup class
    Represent the content of a foreman hostgroup as a dict
    """

    objName = 'hostgroups'
    payloadObj = 'hostgroup'

    def __init__(self, api, key, *args, **kwargs):
        """ Function __init__
        Represent the content of a foreman object as a dict

        @param api: The foreman api
        @param key: The object Key
        @param *args, **kwargs: the dict representation
        @return RETURN: Itself
        """
        ForemanItem.__init__(self, api, key,
                             self.objName, self.payloadObj,
                             *args, **kwargs)
        self.update({'puppetclass_ids':
                     self.api.list('hostgroups/{}/puppetclass_ids'
                                   .format(key))})
        self.update({'param_ids':
                     list(self.api.list('hostgroups/{}/parameters'
                                        .format(key), only_id=True)

                          .keys())})

    def __setitem__(self, key, attributes):
        """ Function __setitem__
        Set a parameter of a foreman object as a dict

        @param key: The key to modify
        @param attribute: The data
        @return RETURN: The API result
        """
        if key is 'puppetclass_ids':
            payload = {"puppetclass_id": attributes,
                       "hostgroup_class": {"puppetclass_id": attributes}}
            return self.api.create("{}/{}/{}"
                                   .format(self.objName,
                                           self.key,
                                           "puppetclass_ids"),
                                   payload)
        elif key is 'parameters':
            payload = {"parameter": attributes}
            return self.api.create("{}/{}/{}"
                                   .format(self.objName,
                                           self.key,
                                           "parameters"),
                                   payload)
        else:
            payload = {self.payloadObj: {key: attributes}}
            return self.api.set(self.objName, self.key, payload)
