import React, { useEffect, useState } from 'react';
import { useAuth } from './use-auth-client';

import { Nav, Spacing, Header, HeaderModal } from './component';
import { Dashboard, RewardHistory, RewardProgram } from './pages';

import { Layout } from 'antd';
const { Content } = Layout;

const HomePage = () => {
  const menuItems = [
    {
      leftIcon: 'sela',
      text: 'Dashboard',
      children: <Dashboard />,
    },
    {
      leftIcon: 'history',
      text: 'Reward History',
      children: <RewardHistory />,
    },
    { leftIcon: 'gift', text: 'Reward Program', children: <RewardProgram /> },
  ];

  const [selectedMenu, setSelectedMenu] = useState(menuItems[0]);
  const { whoamiActor, logout } = useAuth();
  const [principalId, setPrincipalId] = useState(null);
  const [showProfileMenu, setShowProfileMenu] = useState(false);

  useEffect(() => {
    const getPrincipalId = async () => {
      const whoami = await whoamiActor.whoami();
      setPrincipalId(whoami);
    };

    // Call the async function
    getPrincipalId();
  }, []);

  const handleMenuClick = (menu) => {
    setSelectedMenu(menu);
  };

  const setProfileMenu = () => {
    setShowProfileMenu(!showProfileMenu);
  };

  const handleMoreClick = () => {
    setSelectedMenu(menuItems[1]);
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
              <Header
                title={selectedMenu.text}
                principalId={principalId}
                setProfileMenu={setProfileMenu}
              />
              <HeaderModal
                open={showProfileMenu}
                onCancel={setShowProfileMenu}
                logout={logout}
              />
              <Spacing margin={32} />
              {selectedMenu.text === 'Dashboard' ? (
                <Dashboard handleMoreClick={handleMoreClick} />
              ) : (
                selectedMenu.children
              )}
            </div>
          </Content>
        </Layout>
      </Layout>
    </>
  );
};

export default HomePage;
