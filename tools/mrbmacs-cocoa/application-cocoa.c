#include "mrbmacs-cocoa-internal.h"

#include <unistd.h>

static void
mrbmacs_set_app_shell_path(void)
{
  NSString *shell;
  NSString *output_path;
  NSFileHandle *output_handle;
  NSTask *task;
  NSDate *deadline;
  NSData *output_data;
  NSString *output;
  NSRange start;
  NSRange end;
  NSString *path;

  if (getppid() != 1) {
    return;
  }

  shell = [[[NSProcessInfo processInfo] environment] objectForKey:@"SHELL"];
  if (shell.length == 0 ||
      ![[NSFileManager defaultManager] isExecutableFileAtPath:shell]) {
    return;
  }

  output_path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [[NSUUID UUID] UUIDString]];
  if (![[NSFileManager defaultManager] createFileAtPath:output_path
                                               contents:nil
                                             attributes:nil]) {
    return;
  }

  output_handle = [NSFileHandle fileHandleForWritingAtPath:output_path];
  task = [[[NSTask alloc] init] autorelease];
  [task setLaunchPath:shell];
  [task setArguments:@[
    @"-i", @"-l", @"-c", @"printf '\\036%s\\037' \"$PATH\""
  ]];
  [task setStandardOutput:output_handle];
  [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];

  @try {
    [task launch];
  } @catch (NSException *exception) {
    (void)exception;
    [output_handle closeFile];
    [[NSFileManager defaultManager] removeItemAtPath:output_path error:nil];
    return;
  }

  deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
  while (task.running && deadline.timeIntervalSinceNow > 0) {
    usleep(10000);
  }
  if (task.running) {
    [task terminate];
    [output_handle closeFile];
    [[NSFileManager defaultManager] removeItemAtPath:output_path error:nil];
    return;
  }

  [task waitUntilExit];
  [output_handle closeFile];
  if (task.terminationStatus != EXIT_SUCCESS) {
    [[NSFileManager defaultManager] removeItemAtPath:output_path error:nil];
    return;
  }

  output_data = [NSData dataWithContentsOfFile:output_path];
  [[NSFileManager defaultManager] removeItemAtPath:output_path error:nil];
  output = [[[NSString alloc] initWithData:output_data
                                  encoding:NSUTF8StringEncoding] autorelease];
  if (output == nil) {
    return;
  }

  start = [output rangeOfString:@"\036"];
  if (start.location == NSNotFound) {
    return;
  }
  end = [output rangeOfString:@"\037"
                      options:0
                        range:NSMakeRange(NSMaxRange(start),
                                          output.length - NSMaxRange(start))];
  if (end.location == NSNotFound) {
    return;
  }

  path = [output substringWithRange:NSMakeRange(
    NSMaxRange(start), end.location - NSMaxRange(start)
  )];
  if (path.length > 0) {
    setenv("PATH", path.fileSystemRepresentation, 1);
  }
}

static void
mrbmacs_set_app_default_directory(void)
{
  if (getppid() != 1) {
    return;
  }

  if (![[NSFileManager defaultManager]
        changeCurrentDirectoryPath:NSHomeDirectory()]) {
    fprintf(stderr, "Unable to change directory to the user home\n");
  }
}

@interface MrbmacsApplicationDelegate : NSObject <NSApplicationDelegate>
@end

@implementation MrbmacsApplicationDelegate
- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
  [mrbmacs_pending_open_paths addObjectsFromArray:filenames];
  mrbmacs_application_deliver_pending_open_files();
  [sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}
@end

void
mrbmacs_application_deliver_pending_open_files(void)
{
  NSArray *paths;
  mrb_value path_array;

  if (!mrbmacs_app_ready || NSApp.modalWindow != nil ||
      mrbmacs_pending_open_paths.count == 0) {
    return;
  }

  paths = [mrbmacs_pending_open_paths copy];
  [mrbmacs_pending_open_paths removeAllObjects];
  path_array = mrb_ary_new_capa(mrbmacs_mrb, (mrb_int)paths.count);
  for (NSString *path in paths) {
    mrb_ary_push(
      mrbmacs_mrb, path_array,
      mrb_str_new_cstr(mrbmacs_mrb, path.fileSystemRepresentation)
    );
  }
  [paths release];
  mrb_funcall(
    mrbmacs_mrb, mrbmacs_app, "open_native_files", 1, path_array
  );
  if (mrbmacs_mrb->exc != NULL) {
    mrbmacs_print_mruby_error(mrbmacs_mrb);
  }
}

void
mrbmacs_application_schedule_pending_open_files(void)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    mrbmacs_application_deliver_pending_open_files();
  });
}

static mrb_value
mrbmacs_application_queue_native_file_uri(mrb_state *mrb, mrb_value self)
{
  char *uri_text;
  NSString *uri_string;
  NSString *path;
  NSURL *url;

  (void)self;
  mrb_get_args(mrb, "z", &uri_text);
  uri_string = [NSString stringWithUTF8String:uri_text];
  if (uri_string == nil) {
    return mrb_false_value();
  }
  if (uri_string.isAbsolutePath) {
    path = uri_string;
  } else {
    url = [NSURL URLWithString:uri_string];
    if (url == nil || !url.isFileURL || url.path == nil) {
      return mrb_false_value();
    }
    path = url.path;
  }

  [mrbmacs_pending_open_paths addObject:path];
  mrbmacs_application_deliver_pending_open_files();
  return mrb_true_value();
}

static mrb_value
mrbmacs_application_watch_io_read_event(mrb_state *mrb, mrb_value self)
{
  mrb_value io;
  mrb_value fileno;
  NSNumber *key;
  dispatch_source_t source;

  (void)self;
  mrb_get_args(mrb, "o", &io);
  fileno = mrb_funcall(mrb, io, "fileno", 0);
  key = [NSNumber numberWithLongLong:mrb_integer(fileno)];
  if ([mrbmacs_io_sources objectForKey:key] != nil) {
    return mrb_nil_value();
  }

  source = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_READ,
    (uintptr_t)mrb_integer(fileno),
    0,
    dispatch_get_main_queue()
  );
  if (source == nil) {
    return mrb_nil_value();
  }
  dispatch_source_set_event_handler(source, ^{
    mrb_funcall(
      mrbmacs_mrb, mrbmacs_app, "process_io_read_event", 1, io
    );
    if (mrbmacs_mrb->exc != NULL) {
      mrbmacs_print_mruby_error(mrbmacs_mrb);
    }
  });
  [mrbmacs_io_sources setObject:source forKey:key];
  dispatch_resume(source);
  return mrb_nil_value();
}

static mrb_value
mrbmacs_application_unwatch_io_read_event(mrb_state *mrb, mrb_value self)
{
  mrb_value io;
  mrb_value fileno;
  NSNumber *key;
  dispatch_source_t source;

  (void)self;
  mrb_get_args(mrb, "o", &io);
  fileno = mrb_funcall(mrb, io, "fileno", 0);
  key = [NSNumber numberWithLongLong:mrb_integer(fileno)];
  source = [mrbmacs_io_sources objectForKey:key];
  if (source != nil) {
    dispatch_source_cancel(source);
    [mrbmacs_io_sources removeObjectForKey:key];
  }
  return mrb_nil_value();
}

static void
mrbmacs_cancel_io_sources(void)
{
  for (NSNumber *key in [mrbmacs_io_sources allKeys]) {
    dispatch_source_t source = [mrbmacs_io_sources objectForKey:key];
    dispatch_source_cancel(source);
  }
  [mrbmacs_io_sources removeAllObjects];
}

void
mrbmacs_application_prepare(NSApplication *application)
{
  mrbmacs_set_app_shell_path();
  mrbmacs_set_app_default_directory();
  mrbmacs_pending_open_paths = [[NSMutableArray alloc] init];
  mrbmacs_application_delegate = [[MrbmacsApplicationDelegate alloc] init];
  [application setDelegate:mrbmacs_application_delegate];
  mrbmacs_io_sources = [[NSMutableDictionary alloc] init];
}

void
mrbmacs_application_register_methods(mrb_state *mrb, struct RClass *mrbmacs)
{
  struct RClass *application_class = mrb_class_get_under(
    mrb, mrbmacs, "ApplicationCocoa"
  );
  mrb_define_method(
    mrb, application_class, "watch_io_read_event",
    mrbmacs_application_watch_io_read_event, MRB_ARGS_REQ(1)
  );
  mrb_define_method(
    mrb, application_class, "unwatch_io_read_event",
    mrbmacs_application_unwatch_io_read_event, MRB_ARGS_REQ(1)
  );
  mrb_define_method(
    mrb, application_class, "queue_native_file_uri",
    mrbmacs_application_queue_native_file_uri, MRB_ARGS_REQ(1)
  );
}

void
mrbmacs_application_cleanup(NSApplication *application)
{
  mrbmacs_app_ready = NO;
  [application setDelegate:nil];
  [mrbmacs_application_delegate release];
  [mrbmacs_pending_open_paths release];
  mrbmacs_cancel_io_sources();
  [mrbmacs_io_sources release];
}
