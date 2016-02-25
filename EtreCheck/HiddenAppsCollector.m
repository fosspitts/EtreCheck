/***********************************************************************
 ** Etresoft
 ** John Daniel
 ** Copyright (c) 2014. All rights reserved.
 **********************************************************************/

#import "HiddenAppsCollector.h"
#import "Utilities.h"
#import "LaunchdCollector.h"
#import "NSMutableAttributedString+Etresoft.h"
#import "Model.h"

// Collect "other" files like modern login items.
@implementation HiddenAppsCollector

@synthesize processes = myProcesses;

// Constructor.
- (id) init
  {
  self = [super init];
  
  if(self)
    {
    self.name = @"hiddenapps";
    self.title = NSLocalizedStringFromTable(self.name, @"Collectors", NULL);
    }
    
  return self;
  }

// Destructor.
- (void) dealloc
  {
  self.processes = nil;
  
  [super dealloc];
  }

// Collect user launch agents.
- (void) collect
  {
  [self updateStatus: NSLocalizedString(@"Checking for hidden apps", NULL)];

  // Make sure the base class is setup.
  [super collect];

  [self collectProcesses];
  
  [self collectHiddenApps];
  
  [self printHiddenApps];

  dispatch_semaphore_signal(self.complete);
  }

// Collect all running processes.
- (void) collectProcesses
  {
  NSArray * args = @[ @"-raxww", @"-o", @"pid, comm" ];
  
  NSData * result = [Utilities execute: @"/bin/ps" arguments: args];
  
  NSArray * lines = [Utilities formatLines: result];
  
  NSMutableDictionary * currentProcesses = [NSMutableDictionary dictionary];
  
  for(NSString * line in lines)
    {
    if([line hasPrefix: @"STAT"])
      continue;

    NSNumber * pid = nil;
    NSString * command = nil;

    [self parsePs: line pid: & pid command: & command];
    
    if(pid && command)
      [currentProcesses setObject: command forKey: pid];
    }
    
  myProcesses = [currentProcesses copy];
  }

// Parse a line from the ps command.
- (void) parsePs: (NSString *) line
  pid: (NSNumber **) pid
  command: (NSString **) command
  {
  NSScanner * scanner = [NSScanner scannerWithString: line];

  NSInteger pidValue;
  
  bool found = [scanner scanInteger: & pidValue];

  if(!found)
    return;

  *pid = [NSNumber numberWithInteger: pidValue];
  
  [scanner scanUpToString: @"\n" intoString: command];
  }

// Collect apps that weren't printed elsewhere.
- (void) collectHiddenApps
  {
  for(NSString * bundleID in [self.launchdStatus allKeys])
    {
    NSMutableDictionary * status =
      [self collectJobStatusForLabel: bundleID];
    
    [self updateDynamicStatus: status];
    
    [self updateAppleCounts: status];
    }
  }

// Print apps that weren't printed elsewhere.
- (void) printHiddenApps
  {
  bool titlePrinted = NO;
  bool unprintedItems = NO;
  
  NSArray * sortedBundleIDs =
    [[self.launchdStatus allKeys]
      sortedArrayUsingSelector: @selector(compare:)];

  for(NSString * bundleID in sortedBundleIDs)
    {
    NSMutableDictionary * status =
      [self collectJobStatusForLabel: bundleID];
    
    if([[status objectForKey: kPrinted] boolValue])
      continue;
      
    if([[status objectForKey: kIgnored] boolValue])
      continue;
      
    [self updateDynamicStatus: status];
    
    if([[status objectForKey: kIgnored] boolValue])
      continue;
      
    if(!titlePrinted)
      {
      [self.result appendAttributedString: [self buildTitle]];
      titlePrinted = YES;
      }
      
    [self.result
      appendAttributedString: [self formatPropertyListStatus: status]];
    
    [self.result appendString: bundleID];
    
    [self.result appendString: @"\n"];
  
    unprintedItems = YES;
    }
    
  if([[Model model] hideAppleTasks])
    if([self formatAppleCounts: self.result])
      unprintedItems = YES;

  if(unprintedItems)
    [self.result appendCR];
  }

// Get a status and expand with all the information I can find.
- (void) updateDynamicStatus: (NSMutableDictionary *) status
  {
  [self updateDynamicTask: status domain: @"user"];
  [self updateDynamicTask: status domain: @"gui"];
  
  // I'm only guaranteed of having a Label here, not necessarily a
  // bundle ID.
  NSString * label = [status objectForKey: @"Label"];
  
  NSNumber * ignore =
    [NSNumber numberWithBool: [[Model model] hideAppleTasks]];
  
  bool isApple = [self isAppleFile: label];
  
  [status setObject: [NSNumber numberWithBool: isApple] forKey: kApple];

  if(isApple && ([[Model model] majorOSVersion] < kYosemite))
    {
    [status setObject: ignore forKey: kIgnored];
    return;
    }
    
  NSString * executable =
    [self getExecutableForBundle: label status: status];
    
  if(isApple)
    {
    // Sometimes these don't have executables.
    if(!executable)
      {
      [status setObject: ignore forKey: kIgnored];
      
      return;
      }
      
    [status
      setObject: [Utilities checkAppleExecutable: executable]
      forKey: kSignature];
    
    if([[status objectForKey: kSignature] isEqualToString: kSignatureValid])
      [status setObject: ignore forKey: kIgnored];
      
    // Should I ignore this failure?
    if([self ignoreInvalidSignatures: label])
      [status setObject: ignore forKey: kIgnored];
    }
  }

// Get the executable for the app.
- (NSString *) getExecutableForBundle: (NSString *) bundleID
  status: (NSMutableDictionary *) status
  {
  NSString * executable = nil;
  NSArray * command = [status objectForKey: kCommand];
  
  if(!command)
    {
    command = [self collectLaunchdItemCommand: status];
    
    if([command count])
      {
      executable = [self collectLaunchdItemExecutable: command];

      if([executable length])
        {
        [status setObject: command forKey: kCommand];
        [status setObject: executable forKey: kExecutable];
        }
      }
    }
    
  executable = [status objectForKey: kExecutable];
  
  // Next try NSWorkspace.
  if(![executable length])
    executable =
      [[NSWorkspace sharedWorkspace]
        absolutePathForAppBundleWithIdentifier: bundleID];
    
  // Now try ps.
  if(![executable length])
    executable = [self.processes objectForKey: [status objectForKey: kPID]];
    
  if([executable length] && ![command count])
    {
    [status setObject: executable forKey: kExecutable];
    [status
      setObject: [NSArray arrayWithObject: executable] forKey: kCommand];
    }
    
  return executable;
  }

@end
