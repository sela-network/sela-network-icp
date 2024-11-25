import React, { useState } from 'react';

import { Container, Text, Spacing } from '../component';
import StackedChart from './charts/StackedChart';

import { Button } from 'antd';
import Color from '../style/Color';

const Dashboard = ({ handleMoreClick }) => {
  return (
    <Container>
      <Text children="Reward Statistics" weight="semiBold" size={16} />
      <Spacing />
      <div
        style={{
          display: 'flex',
          flexDirection: 'row',
          justifyContent: 'space-between',
        }}
      >
        <Text
          children="This graph shows the total sum of node participation and referral and mission rewards."
          size={14}
        />
        <Button
          shape="round"
          size={20}
          style={{
            backgroundColor: Color.yellow,
            borderColor: Color.yellow,
            width: 66,
            height: 26,
          }}
          onClick={handleMoreClick}
        >
          <Text children="More" size={14} weight="semiBold" color="#000" />
        </Button>
      </div>
      <Spacing margin={32} />
      <StackedChart />
    </Container>
  );
};

export default Dashboard;
