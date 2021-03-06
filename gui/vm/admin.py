from django.utils.translation import ugettext as _

from freenasUI.api.resources import DeviceResourceMixin, VMResourceMixin
from freenasUI.freeadmin.options import BaseFreeAdmin
from freenasUI.freeadmin.site import site
from freenasUI.vm import models


class DeviceFAdmin(BaseFreeAdmin):

    exclude_fields = ('id', 'attributes')
    icon_model = u"VMIcon"
    icon_object = u"VMIcon"
    icon_add = u"AddVMIcon"
    icon_view = u"ViewVMIcon"
    resource_mixin = DeviceResourceMixin

    def get_datagrid_filters(self, request):
        return {
            "vm__id": request.GET.get("id"),
        }


class VMFAdmin(BaseFreeAdmin):

    icon_model = u"VMIcon"
    icon_object = u"VMIcon"
    icon_add = u"AddVMIcon"
    icon_view = u"ViewVMIcon"
    resource_mixin = VMResourceMixin

    def get_actions(self):
        actions = super(VMFAdmin, self).get_actions()
        actions['EditMembers'] = {
            'button_name': _('Devices'),
            'on_click': """function() {
              var mybtn = this;
              for (var i in grid.selection) {
                var data = grid.row(i).data;
                var p = dijit.byId('tab_vm');

                var c = p.getChildren();
                for(var i=0; i<c.length; i++){
                  if(c[i].title == '%(devices)s ' + data.name){
                    p.selectChild(c[i]);
                    return;
                  }
                }

                var pane2 = new dijit.layout.ContentPane({
                  title: '%(devices)s ' + data.name,
                  refreshOnShow: true,
                  closable: true,
                  href: data._device_url
                });
                dojo.addClass(pane2.domNode, [
                 "data_vm_Device" + data.int_name,
                 "objrefresh"
                 ]);
                p.addChild(pane2);
                p.selectChild(pane2);

              }
            }""" % {
                'devices': _('Devices'),
            }}
        actions['Start'] = {
            'button_name': _('Start'),
            'on_click': """function() {
                var mybtn = this;
                for (var i in grid.selection) {
                    var data = grid.row(i).data;
                    editObject('Start', data._start_url, [mybtn,]);
                }
            }""",
            'on_select_after': """function(evt, actionName, action) {
                for(var i=0;i < evt.rows.length;i++) {
                    var row = evt.rows[i];
                    if (row.data.state == 'RUNNING') {
                        query(".grid" + actionName).forEach(function(item, idx) {
                            domStyle.set(item, "display", "none");
                        });
                        break;
                    }
                }
            }""",
        }
        actions['Stop'] = {
            'button_name': _('Stop'),
            'on_click': """function() {
                var mybtn = this;
                for (var i in grid.selection) {
                    var data = grid.row(i).data;
                    editObject('Stop', data._stop_url, [mybtn,]);
                }
            }""",
            'on_select_after': """function(evt, actionName, action) {
                for(var i=0;i < evt.rows.length;i++) {
                    var row = evt.rows[i];
                    if (row.data.state == 'STOPPED') {
                        query(".grid" + actionName).forEach(function(item, idx) {
                            domStyle.set(item, "display", "none");
                        });
                        break;
                    }
                }
            }""",
        }
        return actions

    def get_datagrid_columns(self):
        columns = super(VMFAdmin, self).get_datagrid_columns()
        columns.insert(2, {
            'name': 'info',
            'label': _('Info'),
            'sortable': False,
            'formatter': """function(value,obj) {
                return value;
            }""",
        })
        return columns


site.register(models.Device, DeviceFAdmin)
site.register(models.VM, VMFAdmin)
