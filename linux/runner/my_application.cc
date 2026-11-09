#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// A native move can consume the release of the press delivered to Flutter.
// Reconcile it before the next pointer event, otherwise Flutter drops the next
// click because it still considers the primary button pressed.
static gboolean synchronize_pointer_release(GtkWidget* widget, GdkEvent* event,
                                            gpointer user_data) {
  const char* key = "onexray-primary-button-down";
  GdkEventType type = gdk_event_get_event_type(event);
  guint button = 0;
  if (type == GDK_BUTTON_RELEASE && gdk_event_get_button(event, &button) &&
      button == GDK_BUTTON_PRIMARY) {
    g_object_set_data(G_OBJECT(widget), key, nullptr);
    return FALSE;
  }

  if (type != GDK_MOTION_NOTIFY && type != GDK_ENTER_NOTIFY &&
      type != GDK_BUTTON_PRESS) {
    return FALSE;
  }

  GdkModifierType state;
  gdouble x, y;
  GdkWindow* window = gdk_event_get_window(event);
  GdkDevice* device = gdk_event_get_device(event);
  if (g_object_get_data(G_OBJECT(widget), key) != nullptr &&
      window != nullptr && device != nullptr &&
      gdk_event_get_state(event, &state) && !(state & GDK_BUTTON1_MASK) &&
      gdk_event_get_coords(event, &x, &y)) {
    // Use GTK's normal widget dispatch so the engine and Dart both receive the
    // missing release. Never release a button the current GDK event holds down.
    g_object_set_data(G_OBJECT(widget), key, nullptr);
    GdkEvent* release = gdk_event_new(GDK_BUTTON_RELEASE);
    release->button.window = GDK_WINDOW(g_object_ref(window));
    release->button.send_event = TRUE;
    release->button.time = gdk_event_get_time(event);
    release->button.x = x;
    release->button.y = y;
    release->button.state = state | GDK_BUTTON1_MASK;
    release->button.button = GDK_BUTTON_PRIMARY;
    gdk_event_get_root_coords(event, &release->button.x_root,
                             &release->button.y_root);
    gdk_event_set_device(release, device);
    GdkDevice* source_device = gdk_event_get_source_device(event);
    if (source_device != nullptr) {
      gdk_event_set_source_device(release, source_device);
    }
    gtk_widget_event(widget, release);
    gdk_event_free(release);
  }

  if (type == GDK_BUTTON_PRESS && gdk_event_get_button(event, &button) &&
      button == GDK_BUTTON_PRIMARY) {
    g_object_set_data(G_OBJECT(widget), key, GINT_TO_POINTER(1));
  }
  return FALSE;
}

static void watch_flutter_pointer_events(GtkWidget* widget, gpointer user_data) {
  if (GTK_IS_EVENT_BOX(widget)) {
    // The generic event signal precedes Flutter's type-specific handlers.
    g_signal_connect(widget, "event", G_CALLBACK(synchronize_pointer_release),
                     nullptr);
  }
  if (GTK_IS_CONTAINER(widget)) {
    gtk_container_foreach(GTK_CONTAINER(widget), watch_flutter_pointer_events,
                          nullptr);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  GtkWindow* active_window =
      gtk_application_get_active_window(GTK_APPLICATION(application));
  if (active_window != nullptr) {
    gtk_window_present(active_window);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // GTK owns Linux decorations before the Flutter view is realized. A hidden
  // HeaderBar also requests CSD on X11: the window manager adds no second
  // caption, while GTK keeps its native resize edges and shadow. Flutter draws
  // the visible caption; nativeapi must not replace this titlebar policy.
  gtk_window_set_title(window, "OneXray");
  GtkWidget* header_bar = gtk_header_bar_new();
  gtk_widget_set_no_show_all(header_bar, TRUE);
  gtk_header_bar_set_title(GTK_HEADER_BAR(header_bar), "OneXray");
  gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header_bar), TRUE);
  gtk_window_set_titlebar(window, header_bar);

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_enable_impeller(project, FALSE);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  watch_flutter_pointer_events(GTK_WIDGET(view), nullptr);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Dart controls initial visibility so launch-at-login can remain hidden.
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return FALSE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     static_cast<GApplicationFlags>(
                                         G_APPLICATION_HANDLES_COMMAND_LINE |
                                         G_APPLICATION_HANDLES_OPEN),
                                     nullptr));
}
