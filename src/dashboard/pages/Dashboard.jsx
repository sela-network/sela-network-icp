import React, { useState } from 'react';

import { Container, Text, Spacing, Row, Column } from '../component';
import StackedChart from './charts/StackedChart';

import { Button } from 'antd';
import Color from '../style/Color';

const Dashboard = ({ handleMoreClick }) => {
  const BalanceContainer = ({ title }) => {
    return (
      <Container alignItems="center">
        <Text children={title} weight="semiBold" size={16} />
        <Text children="Uptime: D:00 H:00 M:00" size={14} />
      </Container>
    );
  };

  const ChartContainer = () => {
    return (
      <Container>
        <Text children="Reward Statistics" weight="semiBold" size={16} />
        <Row justifyContent="space-between">
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
        </Row>
        <StackedChart />
      </Container>
    );
  };
  return (
    <>
      <Column>
        <Row>
          <BalanceContainer title="Total Balance" />
          <BalanceContainer title="1 Epoch Earnings" />
          <BalanceContainer title="Today's Earnings" />
        </Row>
        <ChartContainer />
      </Column>
    </>
  );
};

export default Dashboard;
