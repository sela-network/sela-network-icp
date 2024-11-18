import React, { useState } from 'react';
import { useAuth } from './use-auth-client';

import Nav from '/component/Nav.jsx';

import { Layout } from 'antd';
const { Content } = Layout;

function HomePage() {
  const menuItems = [
    { leftIcon: 'sela', text: 'Dashboard' },
    { leftIcon: 'history', text: 'Reward History' },
    { leftIcon: 'gift', text: 'Reward Program' },
  ];

  const [selectedMenu, setSelectedMenu] = useState(menuItems[0]);

  const handleMenuClick = (menu) => {
    setSelectedMenu(menu);
  };

  return (
    <>
      <Layout style={{ minHeight: '100vh' }}>
        <Nav menuItems={menuItems} onMenuClick={handleMenuClick} />

        <Layout style={{ background: '#000', marginLeft: 350 }}>
          <Content
            style={{
              padding: '20px',
              overflow: 'auto', // Allows scrolling when content is too large
            }}
          >
            <div style={{ height: '2000px' }}>
              {' '}
              {/* Make the content area large to demonstrate scrolling */}
              <h2>{selectedMenu.text}</h2>
              <p>
                Lorem Ipsum is simply dummy text of the printing and typesetting
                industry. Lorem Ipsum has been the industry's standard dummy
                text ever since the 1500s, when an unknown printer took a galley
                of type and scrambled it to make a type specimen book. It has
                survived not only five centuries, but also the leap into
                electronic typesetting, remaining essentially unchanged. It was
                popularised in the 1960s with the release of Letraset sheets
                containing Lorem Ipsum passages, and more recently with desktop
                publishing software like Aldus PageMaker including versions of
                Lorem Ipsum.
              </p>
              <p>
                Lorem Ipsum is simply dummy text of the printing and typesetting
                industry. Lorem Ipsum has been the industry's standard dummy
                text ever since the 1500s, when an unknown printer took a galley
                of type and scrambled it to make a type specimen book. It has
                survived not only five centuries, but also the leap into
                electronic typesetting, remaining essentially unchanged. It was
                popularised in the 1960s with the release of Letraset sheets
                containing Lorem Ipsum passages, and more recently with desktop
                publishing software like Aldus PageMaker including versions of
                Lorem Ipsum.
              </p>
              <p>
                Lorem Ipsum is simply dummy text of the printing and typesetting
                industry. Lorem Ipsum has been the industry's standard dummy
                text ever since the 1500s, when an unknown printer took a galley
                of type and scrambled it to make a type specimen book. It has
                survived not only five centuries, but also the leap into
                electronic typesetting, remaining essentially unchanged. It was
                popularised in the 1960s with the release of Letraset sheets
                containing Lorem Ipsum passages, and more recently with desktop
                publishing software like Aldus PageMaker including versions of
                Lorem Ipsum.
              </p>
              <p>
                Lorem Ipsum is simply dummy text of the printing and typesetting
                industry. Lorem Ipsum has been the industry's standard dummy
                text ever since the 1500s, when an unknown printer took a galley
                of type and scrambled it to make a type specimen book. It has
                survived not only five centuries, but also the leap into
                electronic typesetting, remaining essentially unchanged. It was
                popularised in the 1960s with the release of Letraset sheets
                containing Lorem Ipsum passages, and more recently with desktop
                publishing software like Aldus PageMaker including versions of
                Lorem Ipsum.
              </p>
              <p>
                Lorem Ipsum is simply dummy text of the printing and typesetting
                industry. Lorem Ipsum has been the industry's standard dummy
                text ever since the 1500s, when an unknown printer took a galley
                of type and scrambled it to make a type specimen book. It has
                survived not only five centuries, but also the leap into
                electronic typesetting, remaining essentially unchanged. It was
                popularised in the 1960s with the release of Letraset sheets
                containing Lorem Ipsum passages, and more recently with desktop
                publishing software like Aldus PageMaker including versions of
                Lorem Ipsum.
              </p>
            </div>
          </Content>
        </Layout>
        {/* 
        <Layout style={{ background: '#000' }}>
          <Content
            style={{
              margin: '24px 16px 0 16px',
            }}
          >
            <div
              style={{
                padding: 24,
                minHeight: 1360,
                background: '#1D1D1D',
                borderRadius: 16,
              }}
            >
              content lorem ipsum
            </div>
          </Content>
        </Layout> */}
      </Layout>
    </>
  );
}

export default HomePage;
