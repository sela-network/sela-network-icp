import React, { useState } from 'react';
import { useAuth } from './use-auth-client';

import { Nav, Text, Spacing } from './component';
import { Dashboard, RewardHistory, RewardProgram } from './pages';

import { Layout } from 'antd';
const { Content } = Layout;

const HomePage = () => {
  const menuItems = [
    { leftIcon: 'sela', text: 'Dashboard', children: <Dashboard /> },
    {
      leftIcon: 'history',
      text: 'Reward History',
      children: <RewardHistory />,
    },
    { leftIcon: 'gift', text: 'Reward Program', children: <RewardProgram /> },
  ];

  const [selectedMenu, setSelectedMenu] = useState(menuItems[1]);

  const handleMenuClick = (menu) => {
    setSelectedMenu(menu);
  };

  return (
    <>
      <Layout style={{ minHeight: '100vh' }}>
        <Nav
          menuItems={menuItems}
          onMenuClick={handleMenuClick}
          selectedMenu={selectedMenu}
        />

        <Layout style={{ background: '#000', marginLeft: 350 }}>
          <Content
            style={{
              padding: '20px',
              overflow: 'auto', // Allows scrolling when content is too large
            }}
          >
            <div
              style={{
                width: '100%',
                height: '2000px',
                marginTop: 35,
                textAlign: 'left',
              }}
            >
              {' '}
              <Text children={selectedMenu.text} size="24" />
              <Spacing margin={32} />
              {selectedMenu.children}
            </div>
          </Content>
        </Layout>
      </Layout>
    </>
  );
};

export default HomePage;
