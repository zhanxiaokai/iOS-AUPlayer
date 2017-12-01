//
//  AUGraphPlayer.h
//  AUPlayer
//
//  Created by apple on 2017/2/9.
//  Copyright © 2017年 xiaokai.zhan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AUGraphPlayer : NSObject

- (id) initWithFilePath:(NSString*) path;

- (BOOL)play;

- (void)stop;

- (void) setInputSource:(BOOL) isAcc;
@end
