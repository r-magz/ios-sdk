#import "NSBundle+Resources.h"
#import "CardKViewController.h"

@implementation NSBundle (Resources)

NSString *const BUNDLE_NAME = @"CardKit";

+(NSBundle*) resourcesBundle {
    NSBundle *classBundle = [NSBundle bundleForClass:[CardKViewController class]];
    NSBundle *resourcesBundle = [NSBundle bundleWithPath:[classBundle pathForResource:BUNDLE_NAME ofType:@"bundle"]];
    return resourcesBundle ?: classBundle ;
}

+(NSBundle*) languageBundle:(nullable NSString*)language {
    NSBundle *resourcesBundle = [NSBundle resourcesBundle];
    
    if (language == nil) { return  resourcesBundle; }
    
    NSBundle *languageBundle = [NSBundle bundleWithPath:[resourcesBundle pathForResource:language ofType:@"lproj"]];
    return languageBundle ?: resourcesBundle;
}

@end
