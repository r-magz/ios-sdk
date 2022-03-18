#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSBundle (Resources)

+(NSBundle*) resourcesBundle;
+(NSBundle*) languageBundle:(nullable NSString*)language;

@end

NS_ASSUME_NONNULL_END
