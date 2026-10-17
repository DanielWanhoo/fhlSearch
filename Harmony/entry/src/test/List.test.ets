import localUnitTest from './LocalUnit.test';
import idiomSearchServiceTest from './IdiomSearchService.test';

export default function testsuite() {
  localUnitTest();
  idiomSearchServiceTest();
}
