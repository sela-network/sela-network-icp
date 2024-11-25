import React, { useState } from 'react';

import { Container } from '../component';
import StackedBarChart from './charts/StackedBarChart';

const Dashboard = () => {
  return (
    <div>
      <StackedBarChart />
    </div>
  );
};

export default Dashboard;
