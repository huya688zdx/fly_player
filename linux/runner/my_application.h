#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication,
                     my_application,
                     MY,
                     APPLICATION,
                     GtkApplication)

// 创建 GTK 宿主中的 Flutter 应用。
MyApplication* my_application_new();

#endif  // FLUTTER_MY_APPLICATION_H_
