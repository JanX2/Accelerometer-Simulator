//
//  NetworkView.m
//  AccSim
//
//  Created by Otto Chrons on 9/25/08.
//  Copyright 2008 Enzymia Ltd.. All rights reserved.
//

#import "NetworkView.h"
#import "AccelerationInfo.h"
#include <unistd.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <errno.h>


NSString * const	NetworkEnabledKey				= @"com.enzymia.test.AccSim.networkEnabledKey";
NSString * const	NetworkModeKey					= @"com.enzymia.test.AccSim.networkModeKey";
NSString * const	NetworkTargetIPAddressKey		= @"com.enzymia.test.AccSim.networkTargetIPAddress";
NSString * const	NetworkTargetPortKey			= @"com.enzymia.test.AccSim.networkTargetPort";

NSString * const	LoopbackDeviceIPAddress			= @"127.0.0.1";
NSString * const	BroadcastIPAddress				= @"255.255.255.255";


// default UDP port
#define kAccelerometerSimulationPort			10552

// the amount of vertical shift upwards keep the text field in view as the keyboard appears
#define kOFFSET_FOR_KEYBOARD					100.0

// the duration of the animation for the view shift
#define kVerticalOffsetAnimationDuration		0.30

@interface NetworkView (Private)
- (void)switchToMode:(NSInteger)modeIndex;
@end

@implementation NetworkView

@synthesize myTableView;
@synthesize myNavigationBar;

// Override initWithNibName:bundle: to load the view using a nib file then perform additional customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
		NSUInteger networkModeIndex = 1; // default is broadcast

		NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
		[standardUserDefaults registerDefaults:
		 [NSDictionary dictionaryWithObjectsAndKeys:
		  [NSNumber numberWithBool:NO], NetworkEnabledKey, 
		  [NSNumber numberWithInteger:networkModeIndex], NetworkModeKey, 
		  LoopbackDeviceIPAddress, NetworkTargetIPAddressKey, 
		  [NSNumber numberWithInt:kAccelerometerSimulationPort], NetworkTargetPortKey, 
		  nil]];
		
		// create UI controls
		networkMode = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Unicast",@"Broadcast",nil]];
		ipAddressView = [[UITextField alloc] initWithFrame:CGRectZero];
		ipPortView = [[UITextField alloc] initWithFrame:CGRectZero];
		
		// default unicast address is localhost
		NSString *networkTargetIPAddress = [standardUserDefaults valueForKey:NetworkTargetIPAddressKey];
		if (networkTargetIPAddress != nil) {
			self.ipAddress = networkTargetIPAddress;
			ipAddressView.text = self.ipAddress;
		}
		else {
			self.ipAddress = LoopbackDeviceIPAddress;
		}
		
		// start network in previous mode
		NSNumber *networkEnabledFromDefaults = [standardUserDefaults valueForKey:NetworkEnabledKey];
		if (networkEnabledFromDefaults != nil) {
			networkEnabled = [networkEnabledFromDefaults boolValue];
		}
		else {
			networkEnabled = NO;
		}
	
		NSNumber *networkModeFromDefaults = [standardUserDefaults valueForKey:NetworkModeKey];
		if (networkModeFromDefaults != nil) {
			networkModeIndex = [networkModeFromDefaults integerValue];
		}
		[self switchToMode:networkModeIndex];
		networkMode.selectedSegmentIndex = networkModeIndex;
		
		// listen to updates from AccelerometerViewControl
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(accelerationUpdate:) 
													 name:@"AccelerationUpdate" 
												   object:nil];
		// create socket
		udpSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
		// init in broadcast mode
		int broadcast = 1;
		setsockopt(udpSocket, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(int));

		memset((char *) &targetAddress, 0, sizeof(targetAddress));
		targetAddress.sin_family = AF_INET;
		// broadcast address 255.255.255.255
		// TODO: figure out device IP address and netmask, produce a subnet broadcast address
		targetAddress.sin_addr.s_addr = htonl(0xFFFFFFFF);
		targetAddress.sin_len = sizeof(targetAddress);

		NSNumber *networkPortFromDefaults = [standardUserDefaults valueForKey:NetworkTargetPortKey];
		if (networkPortFromDefaults != nil) {
			targetAddress.sin_port = htons([networkPortFromDefaults intValue]);
		}
		else {
			targetAddress.sin_port = htons(kAccelerometerSimulationPort);
		}

    }
    return self;
}

// notification handler for acceleration updates
- (void)accelerationUpdate:(NSNotification*)notification {
	AccelerationInfo* info = (AccelerationInfo*)[notification object];

	// only process is network is enabled and socket initialized OK
	if( networkEnabled && udpSocket != -1 )
	{
		// create UDP packet as formatted string
		// "ACC: <deviceid>,<timestamp>,<x>,<y>,<z>"
		const char *msg = [[NSString stringWithFormat:@"ACC: %s,%.3f,%1.3f,%1.3f,%1.3f\n",[info.deviceID UTF8String],info.absTime,info.x,info.y,info.z] UTF8String];
		int error = sendto(udpSocket, msg, strlen(msg), 0, (struct sockaddr*)&targetAddress, sizeof(targetAddress));
		if( error < 0 )
		{
			//NSLog(@"Socket error %d", errno);
		}
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch( section ) {
		case 0:
			// network enable & broadcast/unicast
			return 2;
		case 1:
			// IP address and port
			return 2;
	}
    return 0;
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (CGFloat)tableView:(UITableView *)aTableView heightForHeaderInSection:(NSInteger)section {
	switch( section ) {
		case 0:
			return 0.0;
		case 1:
			return 25.0;
	}
    return 0.0;
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch( section ) {
		case 0:
			return nil;
		case 1:
			return @"Target";
	}
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell;
	
	switch (indexPath.section*10 + indexPath.row) {
		case 00:
			// create Network enabled switch
			cell = (UITableViewCell*)[tableView dequeueReusableCellWithIdentifier:@"NetEnabled"];
			if (cell == nil) {
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"NetEnabled"];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;

				CGRect rect = CGRectMake(195.0, 8.0, 60.0, 40.0);
				UISwitch *onOffSwitch = [[UISwitch alloc] initWithFrame:rect];
				[onOffSwitch addTarget:self 
								action:@selector(networkToggled:) 
					  forControlEvents:UIControlEventValueChanged];
				[onOffSwitch setOn:networkEnabled];
				[cell.contentView addSubview:onOffSwitch];
				[onOffSwitch release];
				
				rect = CGRectMake(20, 0, 150, 40);
				UILabel *title = [[UILabel alloc] initWithFrame:rect];
				[title setText:@"Network"];
				[cell.contentView addSubview:title];
				[title release];
				
				[cell autorelease];
			}
			return cell;
		case 01:
			// create Unicast | Broadcast selector
			cell = (UITableViewCell*)[tableView dequeueReusableCellWithIdentifier:@"NetMode"];
			if (cell == nil) {
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"NetMode"];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				
				CGRect rect = CGRectMake(139, 7, 170, 30);
				networkMode.frame = rect;
				networkMode.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight;
				networkMode.segmentedControlStyle = UISegmentedControlStyleBar;
				[networkMode addTarget:self 
									 action:@selector(modeChanged:) 
						   forControlEvents:UIControlEventValueChanged];
				[cell.contentView addSubview:networkMode];
				
				rect = CGRectMake(20, 0, 95, 40);
				UILabel *title = [[UILabel alloc] initWithFrame:rect];
				[title setText:@"Mode"];
				[cell.contentView addSubview:title];
				[title release];
				
				[cell autorelease];
			}
			return cell;
		case 10:
			cell = (UITableViewCell*)[tableView dequeueReusableCellWithIdentifier:@"IPAddress"];
			if (cell == nil) {
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"IPAddress"];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				
				CGRect rect = CGRectMake(139, 7, 150, 26);
				ipAddressView.frame = rect;
				ipAddressView.textColor = [UIColor lightGrayColor];
				ipAddressView.borderStyle = UITextBorderStyleRoundedRect;
				// input is IP address, so use numbers and dots keyboard
				ipAddressView.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
				// init in broadcast mode
				ipAddressView.text = BroadcastIPAddress;
				ipAddressView.enabled = NO;

				// delegate is needed for keyboard control
				[ipAddressView setDelegate:self];
				[cell.contentView addSubview:ipAddressView];
				
				rect = CGRectMake(20, 0, 100, 40);
				UILabel *title = [[UILabel alloc] initWithFrame:rect];
				[title setText:@"Address"];
				[cell.contentView addSubview:title];
				[title release];
				
				[cell autorelease];
			}
			return cell;
		case 11:
			cell = (UITableViewCell*)[tableView dequeueReusableCellWithIdentifier:@"IPPort"];
			if (cell == nil) {
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"IPPort"];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				
				CGRect rect = CGRectMake(139, 7, 150, 26);
				ipPortView.frame = rect;
				ipPortView.borderStyle = UITextBorderStyleRoundedRect;
				ipPortView.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
				// contents equals to current port, remember to convert net->host
				ipPortView.text = [NSString stringWithFormat:@"%d",ntohs(targetAddress.sin_port)];

				// delegate is needed for keyboard control
				[ipPortView setDelegate:self];
				[cell.contentView addSubview:ipPortView];
				
				rect = CGRectMake(20, 0, 100, 40);
				UILabel *title = [[UILabel alloc] initWithFrame:rect];
				[title setText:@"Port"];
				[cell.contentView addSubview:title];
				[title release];
				
				[cell autorelease];
			}
			return cell;
	}
	return nil;
}

// Animate the entire view up or down, to prevent the keyboard from covering the author field.
- (void)setViewMovedUp:(BOOL)movedUp
{
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.3];
    // Make changes to the view's frame inside the animation block. They will be animated instead
    // of taking place immediately.
    CGRect rect = self.view.frame;
    if (movedUp)
	{
        // If moving up, not only decrease the origin but increase the height so the view 
        // covers the entire screen behind the keyboard.
        rect.origin.y -= kOFFSET_FOR_KEYBOARD;
        rect.size.height += kOFFSET_FOR_KEYBOARD;
    }
	else
	{
        // If moving down, not only increase the origin but decrease the height.
        rect.origin.y += kOFFSET_FOR_KEYBOARD;
        rect.size.height -= kOFFSET_FOR_KEYBOARD;
    }
    self.view.frame = rect;
    
    [UIView commitAnimations];
}

// called when textfield editing ends (eg. user pressed return)
- (void)textFieldDidEndEditing:(UITextField *)textField {
	if( [textField isEqual:ipAddressView])
	{
		// store IP, convert from text to IP
		self.ipAddress = ipAddressView.text;
		const char *addr = [self.ipAddress UTF8String];
		inet_aton(addr, &targetAddress.sin_addr);
	}
	if( [textField isEqual:ipPortView] )
	{
		// store port, remember host to net conversion
		int port = ipPortView.text.intValue;
		[[NSUserDefaults standardUserDefaults] setInteger:port
												   forKey:NetworkTargetPortKey];
		targetAddress.sin_port = htons(port);
	}
	if  (self.view.frame.origin.y < 0)
	{
		[self setViewMovedUp:NO];
	}
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	// return pressed, close keyboard
	[textField resignFirstResponder];
 	return YES;
}



- (void)textFieldDidBeginEditing:(UITextField *)theTextField
{
	if ([theTextField isEqual:ipAddressView] || [theTextField isEqual:ipPortView])
	{
        // Restore the position of the main view if it was animated to make room for the keyboard.
        if  (self.view.frame.origin.y >= 0)
		{
            [self setViewMovedUp:YES];
        }
    }
}

- (void)keyboardWillShow:(NSNotification *)notif
{
    // The keyboard will be shown. If the user is editing the author, adjust the display so that the
    // author field will not be covered by the keyboard.
    if (([ipAddressView isFirstResponder] || [ipPortView isFirstResponder]) && self.view.frame.origin.y >= 0)
	{
        [self setViewMovedUp:YES];
    }
	else if (!([ipAddressView isFirstResponder] || [ipPortView isFirstResponder]) && self.view.frame.origin.y < 0)
	{
        [self setViewMovedUp:NO];
    }
}

#pragma mark - UIViewController delegate methods

- (void)viewWillAppear:(BOOL)animated
{
    // watch the keyboard so we can adjust the user interface if necessary.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) 
												 name:UIKeyboardWillShowNotification object:self.view.window]; 
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self setEditing:NO animated:YES];
	
    // unregister for keyboard notifications while not visible.
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil]; 
	
    [super viewWillDisappear:animated];
}

- (void)switchToMode:(NSInteger)modeIndex {
	if( modeIndex == 1 )
	{
		// set IP address to broadcast address and disable address text field
		ipAddressView.enabled = NO;
		ipAddressView.textColor = [UIColor lightGrayColor];
		
		// show broadcast address
		ipAddressView.text = BroadcastIPAddress;
		targetAddress.sin_addr.s_addr = htonl(0xFFFFFFFF);
		// enable broadcast mode on socket
		int broadcast = 1;
		setsockopt(udpSocket, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(int));
	}
	else
	{
		modeIndex = 0;
		
		// set IP address to user specified address and enable it
		ipAddressView.enabled = YES;
		ipAddressView.textColor = [UIColor blackColor];
		
		// retrieve stored IP address
		ipAddressView.text = self.ipAddress;
		const char *addr = [self.ipAddress UTF8String];
		inet_aton(addr, &targetAddress.sin_addr);
		
		// disable broadcast mode on socket
		int broadcast = 0;
		setsockopt(udpSocket, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(int));
	}
	
	[[NSUserDefaults standardUserDefaults] setInteger:modeIndex
											   forKey:NetworkModeKey];
}

// switch between broadcast and unicast
- (void)modeChanged:(UISegmentedControl*)control {
	NSLog(@"Mode changed: New value is %d\n", 
		  control.selectedSegmentIndex);
	[[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkModeSwitch" object:control];
	
	[self switchToMode:control.selectedSegmentIndex];
}

// enable/disable network
- (void)networkToggled:(UISwitch*)control {
	NSLog(@"Network toggled: New value is %d\n", 
		  control.on);
	networkEnabled = control.on;
	
	[[NSUserDefaults standardUserDefaults] setBool:networkEnabled
											forKey:NetworkEnabledKey];

}
/*
// Implement loadView to create a view hierarchy programmatically.
- (void)loadView {
}
*/

/*
// Implement viewDidLoad to do additional setup after loading the view.
- (void)viewDidLoad {
    [super viewDidLoad];
}
*/


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning]; // Releases the view if it doesn't have a superview
    // Release anything that's not essential, such as cached data
}


- (void)dealloc {
	[ipAddressView release];
	[ipPortView release];
	[networkMode release];
	
	self.ipAddress = nil;

    [super dealloc];
}


- (NSString *)ipAddress {
    return [[ipAddress retain] autorelease];
}

- (void)setIpAddress:(NSString *)value {
    if (ipAddress != value) {
        [ipAddress release];
        ipAddress = [value copy];
		
		[[NSUserDefaults standardUserDefaults] setObject:ipAddress 
												  forKey:NetworkTargetIPAddressKey];
    }
}



@end
