import abilityTest from './Ability.test';

import localUnitTest from '../../../test/LocalUnit.test';

export default function testsuite() {
  localUnitTest();
  abilityTest();
}