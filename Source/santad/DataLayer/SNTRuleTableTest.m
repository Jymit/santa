/// Copyright 2015 Google Inc. All rights reserved.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///    http://www.apache.org/licenses/LICENSE-2.0
///
///    Unless required by applicable law or agreed to in writing, software
///    distributed under the License is distributed on an "AS IS" BASIS,
///    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///    See the License for the specific language governing permissions and
///    limitations under the License.

#import <MOLCertificate/MOLCertificate.h>
#import <MOLCodesignChecker/MOLCodesignChecker.h>
#import <XCTest/XCTest.h>

#import "Source/common/SNTRule.h"
#import "Source/santad/DataLayer/SNTRuleTable.h"

/// This test case actually tests SNTRuleTable and SNTRule
@interface SNTRuleTableTest : XCTestCase
@property SNTRuleTable *sut;
@property FMDatabaseQueue *dbq;
@end

@implementation SNTRuleTableTest

- (void)setUp {
  [super setUp];

  self.dbq = [[FMDatabaseQueue alloc] init];
  self.sut = [[SNTRuleTable alloc] initWithDatabaseQueue:self.dbq];
}

- (SNTRule *)_exampleTeamIDRule {
  SNTRule *r = [[SNTRule alloc] init];
  r.identifier = @"teamID";
  r.state = SNTRuleStateBlock;
  r.type = SNTRuleTypeTeamID;
  r.customMsg = @"A teamID rule";
  return r;
}

- (SNTRule *)_exampleBinaryRule {
  SNTRule *r = [[SNTRule alloc] init];
  r.identifier = @"a";
  r.state = SNTRuleStateBlock;
  r.type = SNTRuleTypeBinary;
  r.customMsg = @"A rule";
  return r;
}

- (SNTRule *)_exampleCertRule {
  SNTRule *r = [[SNTRule alloc] init];
  r.identifier = @"b";
  r.state = SNTRuleStateAllow;
  r.type = SNTRuleTypeCertificate;
  return r;
}

- (void)testAddRulesNotClean {
  NSUInteger ruleCount = self.sut.ruleCount;
  NSUInteger binaryRuleCount = self.sut.binaryRuleCount;

  NSError *error;
  [self.sut addRules:@[ [self _exampleBinaryRule] ] cleanSlate:NO error:&error];

  XCTAssertEqual(self.sut.ruleCount, ruleCount + 1);
  XCTAssertEqual(self.sut.binaryRuleCount, binaryRuleCount + 1);
  XCTAssertNil(error);
}

- (void)testAddRulesClean {
  // Add a binary rule without clean slate
  NSError *error = nil;
  XCTAssertTrue([self.sut addRules:@[ [self _exampleBinaryRule] ] cleanSlate:NO error:&error]);
  XCTAssertNil(error);

  // Now add a cert rule with a clean slate, assert that the binary rule was removed
  error = nil;
  XCTAssertTrue(([self.sut addRules:@[ [self _exampleCertRule] ] cleanSlate:YES error:&error]));
  XCTAssertEqual([self.sut binaryRuleCount], 0);
  XCTAssertNil(error);
}

- (void)testAddMultipleRules {
  NSUInteger ruleCount = self.sut.ruleCount;

  NSError *error;
  [self.sut
      addRules:@[ [self _exampleBinaryRule], [self _exampleCertRule], [self _exampleBinaryRule] ]
    cleanSlate:NO
         error:&error];

  XCTAssertEqual(self.sut.ruleCount, ruleCount + 2);
  XCTAssertNil(error);
}

- (void)testAddRulesEmptyArray {
  NSError *error;
  XCTAssertFalse([self.sut addRules:@[] cleanSlate:YES error:&error]);
  XCTAssertEqual(error.code, SNTRuleTableErrorEmptyRuleArray);
}

- (void)testAddRulesNilArray {
  NSError *error;
  XCTAssertFalse([self.sut addRules:nil cleanSlate:YES error:&error]);
  XCTAssertEqual(error.code, SNTRuleTableErrorEmptyRuleArray);
}

- (void)testAddInvalidRule {
  SNTRule *r = [[SNTRule alloc] init];
  r.identifier = @"a";
  r.type = SNTRuleTypeCertificate;

  NSError *error;
  XCTAssertFalse([self.sut addRules:@[ r ] cleanSlate:NO error:&error]);
  XCTAssertEqual(error.code, SNTRuleTableErrorInvalidRule);
}

- (void)testFetchBinaryRule {
  [self.sut addRules:@[ [self _exampleBinaryRule], [self _exampleCertRule] ]
          cleanSlate:NO
               error:nil];

  SNTRule *r = [self.sut ruleForBinarySHA256:@"a" certificateSHA256:nil teamID:nil];
  XCTAssertNotNil(r);
  XCTAssertEqualObjects(r.identifier, @"a");
  XCTAssertEqual(r.type, SNTRuleTypeBinary);

  r = [self.sut ruleForBinarySHA256:@"b" certificateSHA256:nil teamID:nil];
  XCTAssertNil(r);
}

- (void)testFetchCertificateRule {
  [self.sut addRules:@[ [self _exampleBinaryRule], [self _exampleCertRule] ]
          cleanSlate:NO
               error:nil];

  SNTRule *r = [self.sut ruleForBinarySHA256:nil certificateSHA256:@"b" teamID:nil];
  XCTAssertNotNil(r);
  XCTAssertEqualObjects(r.identifier, @"b");
  XCTAssertEqual(r.type, SNTRuleTypeCertificate);

  r = [self.sut ruleForBinarySHA256:nil certificateSHA256:@"a" teamID:nil];
  XCTAssertNil(r);
}

- (void)testFetchTeamIDRule {
  [self.sut addRules:@[ [self _exampleBinaryRule], [self _exampleTeamIDRule] ]
          cleanSlate:NO
               error:nil];

  SNTRule *r = [self.sut ruleForBinarySHA256:nil certificateSHA256:nil teamID:@"teamID"];
  XCTAssertNotNil(r);
  XCTAssertEqualObjects(r.identifier, @"teamID");
  XCTAssertEqual(r.type, SNTRuleTypeTeamID);
  XCTAssertEqual([self.sut teamIDRuleCount], 1);

  r = [self.sut ruleForBinarySHA256:nil certificateSHA256:nil teamID:@"nonexistentTeamID"];
  XCTAssertNil(r);
}

- (void)testFetchRuleOrdering {
  [self.sut
      addRules:@[ [self _exampleCertRule], [self _exampleBinaryRule], [self _exampleTeamIDRule] ]
    cleanSlate:NO
         error:nil];

  // This test verifies that the implicit rule ordering we've been abusing is still working.
  // See the comment in SNTRuleTable#ruleForBinarySHA256:certificateSHA256:teamID
  SNTRule *r = [self.sut ruleForBinarySHA256:@"a" certificateSHA256:@"b" teamID:@"teamID"];
  XCTAssertNotNil(r);
  XCTAssertEqualObjects(r.identifier, @"a");
  XCTAssertEqual(r.type, SNTRuleTypeBinary, @"Implicit rule ordering failed");

  r = [self.sut ruleForBinarySHA256:@"a" certificateSHA256:@"unknowncert" teamID:@"teamID"];
  XCTAssertNotNil(r);
  XCTAssertEqualObjects(r.identifier, @"a");
  XCTAssertEqual(r.type, SNTRuleTypeBinary, @"Implicit rule ordering failed");

  r = [self.sut ruleForBinarySHA256:@"unknown" certificateSHA256:@"b" teamID:@"teamID"];
  XCTAssertNotNil(r);
  XCTAssertEqualObjects(r.identifier, @"b");
  XCTAssertEqual(r.type, SNTRuleTypeCertificate, @"Implicit rule ordering failed");
}

- (void)testBadDatabase {
  NSString *dbPath = [NSTemporaryDirectory() stringByAppendingString:@"sntruletabletest_baddb.db"];
  [@"some text" writeToFile:dbPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];

  FMDatabaseQueue *dbq = [[FMDatabaseQueue alloc] initWithPath:dbPath];
  SNTRuleTable *sut = [[SNTRuleTable alloc] initWithDatabaseQueue:dbq];

  [sut addRules:@[ [self _exampleBinaryRule] ] cleanSlate:NO error:nil];
  XCTAssertGreaterThan(sut.ruleCount, 0);

  [[NSFileManager defaultManager] removeItemAtPath:dbPath error:NULL];
}

@end
