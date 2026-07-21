import re

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Modify _can_drop_data
can_drop_old = '''\t\tvar root = get_node("/root/MainLab")
\t\tif category == "hull":
\t\t\tif root and root.get_node_or_null("Hull") != null:
\t\t\t\t# Cannot drop hull if hull already exists
\t\t\t\t_destroy_ghost_mesh()
\t\t\t\treturn false
\t\t\t_update_ghost_mesh_hull(type_id)
\t\t\treturn true'''

can_drop_new = '''\t\tvar root = get_node("/root/MainLab")
\t\tif category == "hull":
\t\t\t_update_ghost_mesh_hull(type_id)
\t\t\treturn true'''

content = content.replace(can_drop_old, can_drop_new)

# Modify _drop_data
drop_old = '''\t\tvar root = get_node("/root/MainLab")
\t\tif category == "hull":
\t\t\tif root and root.has_method("_place_hull_from_ui"):
\t\t\t\troot._place_hull_from_ui(type_id)'''

drop_new = '''\t\tvar root = get_node("/root/MainLab")
\t\tif category == "hull":
\t\t\tif root:
\t\t\t\tvar existing_hull = root.get_node_or_null("Hull")
\t\t\t\tif existing_hull:
\t\t\t\t\t# Auto-delete existing hull before placing new one
\t\t\t\t\troot.hull = null
\t\t\t\t\texisting_hull.queue_free()
\t\t\t\tif root.has_method("_place_hull_from_ui"):
\t\t\t\t\troot._place_hull_from_ui(type_id)'''

content = content.replace(drop_old, drop_new)

with open('e:/Build-A-Bomber/prototype/scripts/drag_drop_manager.gd', 'w', encoding='utf-8') as f:
    f.write(content)
